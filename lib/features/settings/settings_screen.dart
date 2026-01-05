import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/theme_mode_controller.dart';
import '../../core/widgets/section_card.dart';
import '../../data/db/usb_ids_update_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const routeName = 'settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeControllerProvider);
    final updateAsync = ref.watch(usbIdsUpdateControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const _AppHeader(),
            const SizedBox(height: 12),
            _ThemeSection(mode: mode),
            const SizedBox(height: 12),
            updateAsync.when(
              loading: () => const _DbCardLoading(),
              error: (e, _) => _DbCardError(error: e.toString()),
              data: (s) => _UsbIdsDbSection(state: s),
            ),
            const SizedBox(height: 12),
            const _NotesSection(),
          ],
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'USBDevInfo',
      subtitle: 'USB device inspection for Android',
      leading: const Icon(Icons.usb_rounded),
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final info = snap.data;
          final version = info == null ? '—' : '${info.version} (${info.buildNumber})';
          final pkg = info?.packageName ?? '—';
          return Column(
            children: [
              _InfoRow(label: 'Version', value: version),
              _InfoRow(label: 'Package', value: pkg),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeSection extends ConsumerWidget {
  const _ThemeSection({required this.mode});
  final ThemeMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Appearance',
      subtitle: 'Theme mode',
      leading: const Icon(Icons.palette_outlined),
      child: Column(
        children: [
          RadioListTile<ThemeMode>(
            value: ThemeMode.system,
            groupValue: mode,
            onChanged: (v) => ref.read(themeModeControllerProvider.notifier).setThemeMode(v!),
            title: const Text('System'),
            subtitle: const Text('Follow device setting'),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.light,
            groupValue: mode,
            onChanged: (v) => ref.read(themeModeControllerProvider.notifier).setThemeMode(v!),
            title: const Text('Light'),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.dark,
            groupValue: mode,
            onChanged: (v) => ref.read(themeModeControllerProvider.notifier).setThemeMode(v!),
            title: const Text('Dark'),
          ),
        ],
      ),
    );
  }
}

class _DbCardLoading extends StatelessWidget {
  const _DbCardLoading();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'USB IDs database',
      subtitle: 'linux-usb.org',
      leading: const Icon(Icons.storage_rounded),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading database info…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DbCardError extends StatelessWidget {
  const _DbCardError({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'USB IDs database',
      subtitle: 'linux-usb.org',
      leading: const Icon(Icons.storage_rounded),
      child: Text(error),
    );
  }
}

class _UsbIdsDbSection extends ConsumerWidget {
  const _UsbIdsDbSection({required this.state});
  final UsbIdsUpdateState state;

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '—';
    final s = dt.toLocal().toIso8601String().replaceFirst('T', ' ');
    return s.split('.').first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = state.localMeta;

    final hint = state.updateAvailableHint;
    final busy = state.busy;

    final statusText = state.error != null
        ? (state.message ?? 'Update failed')
        : (state.message ??
            (hint ? 'Update may be available' : 'Database is ready'));

    return SectionCard(
      title: 'USB IDs database',
      subtitle: hint ? 'Update may be available' : 'linux-usb.org',
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.storage_rounded),
          if (hint)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      child: Column(
        children: [
          _InfoRow(label: 'Installed version', value: meta.versionLabel),
          _InfoRow(label: 'Installed date', value: meta.dateLabel),
          _InfoRow(label: 'Checksum (FNV-1a 64)', value: meta.checksumLabel),
          _InfoRow(label: 'Last checked', value: _fmtTime(state.lastCheckedAt)),
          const SizedBox(height: 10),

          // Status / progress
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                state.error != null
                    ? Icons.error_outline_rounded
                    : busy
                        ? Icons.hourglass_top_rounded
                        : Icons.info_outline_rounded,
                color: state.error != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: state.error != null
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          if (busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: state.progress),
          ],

          const SizedBox(height: 14),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-check weekly'),
            subtitle: const Text('Uses lightweight network headers (ETag/Last-Modified).'),
            value: state.autoCheckEnabled,
            onChanged: busy
                ? null
                : (v) => ref
                    .read(usbIdsUpdateControllerProvider.notifier)
                    .setAutoCheckEnabled(v),
          ),

          const SizedBox(height: 10),

          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => ref
                      .read(usbIdsUpdateControllerProvider.notifier)
                      .checkAndUpdateNow(),
              icon: const Icon(Icons.system_update_alt_rounded),
              label: Text(hint ? 'Check & update' : 'Check now'),
            ),
          ),

          if (state.error != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                state.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Notes',
      subtitle: 'How this app reads device info',
      leading: const Icon(Icons.info_outline_rounded),
      child: Text(
        'Vendor/product names come from the local usb.ids database (linux-usb.org).\n\n'
        'Some fields (manufacturer/product/serial strings and raw descriptors) require per-device permission on Android. '
        'If you see missing descriptor details, open the device and grant permission.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
