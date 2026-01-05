import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/theme/theme_mode_controller.dart';
import '../../core/utils/fnv1a64.dart';
import '../usb/providers.dart';
import '../usb/usb_repository.dart';
import 'usb_ids_db.dart';
import 'usb_ids_db_builder.dart';
import 'usb_ids_db_meta.dart';

/*
  Remote sources (prefer HTTPS, fallback to HTTP).
*/
final List<Uri> _usbIdsUris = <Uri>[
  Uri.parse('https://www.linux-usb.org/usb.ids'),
  Uri.parse('http://www.linux-usb.org/usb.ids'),
];

/* SharedPreferences keys */
const _kAutoCheckEnabled = 'usbids_auto_check_enabled_v1';
const _kLastCheckedAtIso = 'usbids_last_checked_at_iso_v1';
const _kRemoteEtag = 'usbids_remote_etag_v1';
const _kRemoteLastModified = 'usbids_remote_last_modified_v1';
const _kUpdateAvailableHint = 'usbids_update_available_hint_v1';

enum UsbIdsUpdatePhase {
  idle,
  checking,
  downloading,
  buildingDb,
  installing,
  done,
  error,
}

class UsbIdsUpdateState {
  const UsbIdsUpdateState({
    required this.localMeta,
    required this.autoCheckEnabled,
    required this.updateAvailableHint,
    this.lastCheckedAt,
    this.phase = UsbIdsUpdatePhase.idle,
    this.progress,
    this.message,
    this.error,
  });

  final UsbIdsDbMeta localMeta;
  final bool autoCheckEnabled;
  final bool updateAvailableHint;
  final DateTime? lastCheckedAt;

  final UsbIdsUpdatePhase phase;
  final double? progress; // 0..1 during download, null if unknown
  final String? message;
  final String? error;

  bool get busy =>
      phase == UsbIdsUpdatePhase.checking ||
      phase == UsbIdsUpdatePhase.downloading ||
      phase == UsbIdsUpdatePhase.buildingDb ||
      phase == UsbIdsUpdatePhase.installing;

  UsbIdsUpdateState copyWith({
    UsbIdsDbMeta? localMeta,
    bool? autoCheckEnabled,
    bool? updateAvailableHint,
    DateTime? lastCheckedAt,
    UsbIdsUpdatePhase? phase,
    double? progress,
    String? message,
    String? error,
  }) {
    return UsbIdsUpdateState(
      localMeta: localMeta ?? this.localMeta,
      autoCheckEnabled: autoCheckEnabled ?? this.autoCheckEnabled,
      updateAvailableHint: updateAvailableHint ?? this.updateAvailableHint,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      phase: phase ?? this.phase,
      progress: progress,
      message: message,
      error: error,
    );
  }
}

final usbIdsUpdateControllerProvider =
    AsyncNotifierProvider<UsbIdsUpdateController, UsbIdsUpdateState>(
  UsbIdsUpdateController.new,
);

/*
  Optional: run a lightweight HEAD check on startup (if enabled).
  Wire this from main.dart (already done in the provided main.dart).
*/
final usbIdsAutoCheckCoordinatorProvider = Provider<void>((ref) {
  unawaited(
    ref.read(usbIdsUpdateControllerProvider.notifier).backgroundCheckIfDue(),
  );
});

class UsbIdsUpdateController extends AsyncNotifier<UsbIdsUpdateState> {
  @override
  Future<UsbIdsUpdateState> build() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);

    final auto = prefs.getBool(_kAutoCheckEnabled) ?? false;
    final hint = prefs.getBool(_kUpdateAvailableHint) ?? false;

    final lastIso = prefs.getString(_kLastCheckedAtIso);
    final last = DateTime.tryParse((lastIso ?? '').trim());

    final db = await ref.read(usbIdsDbProvider.future);
    final meta = await db.readMeta();

    return UsbIdsUpdateState(
      localMeta: meta,
      autoCheckEnabled: auto,
      updateAvailableHint: hint,
      lastCheckedAt: last,
      phase: UsbIdsUpdatePhase.idle,
    );
  }

  Future<void> setAutoCheckEnabled(bool v) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_kAutoCheckEnabled, v);

    final cur = state.value;
    if (cur != null) {
      state = AsyncValue.data(cur.copyWith(autoCheckEnabled: v));
    } else {
      state = AsyncValue.data(await build());
    }
  }

  /*
    HEAD check (cheap signal) every 7 days if enabled.
    Updates only the "hint" flag (ETag/Last-Modified changed).
  */
  Future<void> backgroundCheckIfDue() async {
    final cur = state.value ?? await build();
    if (!cur.autoCheckEnabled) return;

    final now = DateTime.now();
    final last = cur.lastCheckedAt;
    if (last != null && now.difference(last) < const Duration(days: 7)) {
      return;
    }

    final prefs = await ref.read(sharedPreferencesProvider.future);

    try {
      final client = HttpClient();
      try {
        HttpClientResponse? resp;
        for (final uri in _usbIdsUris) {
          try {
            final req = await client.headUrl(uri);
            req.headers.set(HttpHeaders.acceptHeader, 'text/plain,*/*');
            resp = await req.close();
            break;
          } catch (_) {
            // try next
          }
        }
        if (resp == null) return;

        await resp.drain();

        final etag = resp.headers.value(HttpHeaders.etagHeader);
        final lm = resp.headers.value(HttpHeaders.lastModifiedHeader);

        final prevEtag = prefs.getString(_kRemoteEtag);
        final prevLm = prefs.getString(_kRemoteLastModified);

        bool changed = false;
        if (etag != null && etag.isNotEmpty && etag != prevEtag) changed = true;
        if (lm != null && lm.isNotEmpty && lm != prevLm) changed = true;

        if (etag != null) await prefs.setString(_kRemoteEtag, etag);
        if (lm != null) await prefs.setString(_kRemoteLastModified, lm);

        await prefs.setString(_kLastCheckedAtIso, now.toIso8601String());
        await prefs.setBool(_kUpdateAvailableHint, changed);

        if (ref.mounted) {
          final db = await ref.read(usbIdsDbProvider.future);
          final meta = await db.readMeta();
          state = AsyncValue.data(
            cur.copyWith(
              localMeta: meta,
              lastCheckedAt: now,
              updateAvailableHint: changed,
            ),
          );
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // silent fail for background hint
    }
  }

  /*
    One button: check + download + rebuild + swap if needed.
  */
  Future<void> checkAndUpdateNow() async {
    final initial = state.value ?? await build();

    state = AsyncValue.data(
      initial.copyWith(
        phase: UsbIdsUpdatePhase.checking,
        message: 'Checking for updates…',
        progress: null,
        error: null,
      ),
    );

    final prefs = await ref.read(sharedPreferencesProvider.future);

    // Close and invalidate DB-related providers to release file locks.
    try {
      final liveDb = await ref.read(usbIdsDbProvider.future);
      await liveDb.close();
    } catch (_) {}
    ref.invalidate(usbIdsDbProvider);
    ref.invalidate(usbRepositoryProvider);

    final installedDbPath = await UsbIdsDb.resolvedDbPath();
    final dbDir = await getDatabasesPath();
    final tmpUsbIdsPath = '${dbDir}${Platform.pathSeparator}usb.ids.download';
    final tmpDbPath = '${dbDir}${Platform.pathSeparator}usbids.new.sqlite';

    // Conditional headers
    final prevEtag = prefs.getString(_kRemoteEtag);
    final prevLm = prefs.getString(_kRemoteLastModified);

    final client = HttpClient();

    try {
      HttpClientResponse? resp;
      Uri? usedUri;

      for (final uri in _usbIdsUris) {
        try {
          final req = await client.getUrl(uri);
          req.headers.set(HttpHeaders.acceptHeader, 'text/plain,*/*');

          if (prevEtag != null && prevEtag.trim().isNotEmpty) {
            req.headers.set(HttpHeaders.ifNoneMatchHeader, prevEtag.trim());
          }
          if (prevLm != null && prevLm.trim().isNotEmpty) {
            try {
              req.headers.ifModifiedSince = HttpDate.parse(prevLm.trim());
            } catch (_) {}
          }

          final r = await req.close();
          resp = r;
          usedUri = uri;
          break;
        } catch (_) {
          // try next
        }
      }

      if (resp == null || usedUri == null) {
        throw StateError('Failed to contact linux-usb.org over HTTPS/HTTP.');
      }

      if (resp.statusCode == HttpStatus.notModified) {
        await resp.drain();
        final now = DateTime.now();
        await prefs.setString(_kLastCheckedAtIso, now.toIso8601String());
        await prefs.setBool(_kUpdateAvailableHint, false);

        ref.invalidate(usbIdsDbProvider);
        final reopened = await ref.read(usbIdsDbProvider.future);
        final meta = await reopened.readMeta();

        state = AsyncValue.data(
          initial.copyWith(
            localMeta: meta,
            lastCheckedAt: now,
            updateAvailableHint: false,
            phase: UsbIdsUpdatePhase.done,
            message: 'Already up to date.',
          ),
        );
        return;
      }

      if (resp.statusCode != HttpStatus.ok) {
        final now = DateTime.now();
        await prefs.setString(_kLastCheckedAtIso, now.toIso8601String());
        throw StateError('Update check failed (HTTP ${resp.statusCode}).');
      }

      final newEtag = resp.headers.value(HttpHeaders.etagHeader);
      final newLm = resp.headers.value(HttpHeaders.lastModifiedHeader);
      if (newEtag != null) await prefs.setString(_kRemoteEtag, newEtag);
      if (newLm != null) await prefs.setString(_kRemoteLastModified, newLm);

      // Download + checksum
      state = AsyncValue.data(
        (state.value ?? initial).copyWith(
          phase: UsbIdsUpdatePhase.downloading,
          message: 'Downloading usb.ids…',
          progress: 0,
          error: null,
        ),
      );

      final sink = File(tmpUsbIdsPath).openWrite();
      final fnv = Fnv1a64();
      final total = resp.contentLength; // -1 if unknown
      int received = 0;

      await for (final chunk in resp) {
        sink.add(chunk);
        fnv.addBytes(chunk);
        received += chunk.length;

        final cur = state.value;
        if (cur != null && cur.phase == UsbIdsUpdatePhase.downloading) {
          final prog =
              (total > 0) ? (received / total).clamp(0.0, 1.0) : null;
          state = AsyncValue.data(cur.copyWith(progress: prog));
        }
      }

      await sink.flush();
      await sink.close();

      final checksum = fnv.digestHex().toUpperCase();

      // Compare to currently installed checksum (best-effort)
      UsbIdsDbMeta localMeta;
      try {
        final tmpOpenDb = await UsbIdsDb.open();
        localMeta = await tmpOpenDb.readMeta();
        await tmpOpenDb.close();
      } catch (_) {
        localMeta = initial.localMeta;
      }

      final localChecksum = (localMeta.checksumFnv64 ?? '').trim().toUpperCase();
      final sameChecksum =
          localChecksum.isNotEmpty && localChecksum == checksum.trim();

      final now = DateTime.now();
      await prefs.setString(_kLastCheckedAtIso, now.toIso8601String());

      if (sameChecksum) {
        // Cleanup + reopen
        try {
          await File(tmpUsbIdsPath).delete();
        } catch (_) {}

        await prefs.setBool(_kUpdateAvailableHint, false);

        ref.invalidate(usbIdsDbProvider);
        final reopened = await ref.read(usbIdsDbProvider.future);
        final meta = await reopened.readMeta();

        state = AsyncValue.data(
          initial.copyWith(
            localMeta: meta,
            lastCheckedAt: now,
            updateAvailableHint: false,
            phase: UsbIdsUpdatePhase.done,
            message: 'Already up to date.',
          ),
        );
        return;
      }

      // Build DB
      state = AsyncValue.data(
        (state.value ?? initial).copyWith(
          phase: UsbIdsUpdatePhase.buildingDb,
          message: 'Building database…',
          progress: null,
          error: null,
        ),
      );

      await deleteDatabase(tmpDbPath);
      await UsbIdsDbBuilder.build(
        usbIdsPath: tmpUsbIdsPath,
        outDbPath: tmpDbPath,
        checksumFnv64: checksum,
      );

      // Install (swap)
      state = AsyncValue.data(
        (state.value ?? initial).copyWith(
          phase: UsbIdsUpdatePhase.installing,
          message: 'Installing update…',
        ),
      );

      final installed = File(installedDbPath);
      final newDb = File(tmpDbPath);
      final backup = File('$installedDbPath.bak');

      try {
        if (await backup.exists()) {
          await backup.delete();
        }
      } catch (_) {}

      if (await installed.exists()) {
        try {
          await installed.rename(backup.path);
        } catch (_) {
          try {
            await installed.delete();
          } catch (_) {}
        }
      }

      await newDb.rename(installedDbPath);

      // Cleanup
      try {
        await File(tmpUsbIdsPath).delete();
      } catch (_) {}
      try {
        if (await backup.exists()) await backup.delete();
      } catch (_) {}

      await prefs.setBool(_kUpdateAvailableHint, false);

      // Re-open DB and refresh state
      ref.invalidate(usbIdsDbProvider);
      ref.invalidate(usbRepositoryProvider);

      final reopened = await ref.read(usbIdsDbProvider.future);
      final meta = await reopened.readMeta();

      state = AsyncValue.data(
        initial.copyWith(
          localMeta: meta,
          lastCheckedAt: now,
          updateAvailableHint: false,
          phase: UsbIdsUpdatePhase.done,
          message: 'Database updated.',
        ),
      );
    } catch (e) {
      ref.invalidate(usbIdsDbProvider);
      ref.invalidate(usbRepositoryProvider);

      final cur = state.value ?? initial;
      state = AsyncValue.data(
        cur.copyWith(
          phase: UsbIdsUpdatePhase.error,
          error: e.toString(),
          message: 'Update failed.',
        ),
      );
    } finally {
      client.close(force: true);
    }
  }
}
