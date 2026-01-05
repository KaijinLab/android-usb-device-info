import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_mode_controller.dart';
import '../../../data/usb/models.dart';
import '../../../data/usb/usb_repository.dart';
import '../models/device_history_entry.dart';

const _kHistoryKey = 'device_history_v1';
const _kHistoryMaxItems = 50;

final deviceHistoryControllerProvider =
    AsyncNotifierProvider<DeviceHistoryController, List<DeviceHistoryEntry>>(
        DeviceHistoryController.new);

class DeviceHistoryController extends AsyncNotifier<List<DeviceHistoryEntry>> {
  @override
  Future<List<DeviceHistoryEntry>> build() async {
    return _loadFromPrefs();
  }

  Future<List<DeviceHistoryEntry>> _loadFromPrefs() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final raw = prefs.getString(_kHistoryKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => DeviceHistoryEntry.fromMap(m.cast<Object?, Object?>()))
          .where((e) => e.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveToPrefs(List<DeviceHistoryEntry> items) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final encoded = jsonEncode(items.map((e) => e.toMap()).toList());
    await prefs.setString(_kHistoryKey, encoded);
  }

  Future<void> _upsert(DeviceHistoryEntry entry) async {
    final current = state.asData?.value ?? await _loadFromPrefs();
    final next = <DeviceHistoryEntry>[
      entry,
      ...current.where((e) => e.id != entry.id),
    ];
    final capped = next.length <= _kHistoryMaxItems
        ? next
        : next.take(_kHistoryMaxItems).toList();
    state = AsyncValue.data(capped);
    await _saveToPrefs(capped);
  }

  Future<void> recordFromListItem(UsbDeviceListItem item) async {
    final s = item.device;
    final now = DateTime.now();

    final entry = DeviceHistoryEntry(
      id: _makeStableIdFromSummary(s),
      testedAt: now,
      deviceName: s.deviceName,
      vendorId: s.vendorId,
      productId: s.productId,
      deviceClass: s.deviceClass,
      deviceSubclass: s.deviceSubclass,
      deviceProtocol: s.deviceProtocol,
      interfaceCount: s.interfaceCount,
      configurationCount: s.configurationCount,
      hasPermission: s.hasPermission,
      isInputDevice: s.isInputDevice,
      inputSources: s.inputSources,
      vendorName: item.vendorName,
      productNameResolved: item.productName,
      manufacturerNameRaw: s.manufacturerName,
      productNameRaw: s.productName,
      serialNumber: s.serialNumber,
      usbVersion: s.usbVersion,
      speed: s.speed,
      deviceId: s.deviceId,
      portNumber: s.portNumber,
    );

    await _upsert(entry);
  }

  Future<void> recordFromView(UsbDeviceDetailViewData view) async {
    final s = view.details.summary;
    final now = DateTime.now();

    final entry = DeviceHistoryEntry(
      id: _makeStableIdFromSummary(s),
      testedAt: now,
      deviceName: s.deviceName,
      vendorId: s.vendorId,
      productId: s.productId,
      deviceClass: s.deviceClass,
      deviceSubclass: s.deviceSubclass,
      deviceProtocol: s.deviceProtocol,
      interfaceCount: s.interfaceCount,
      configurationCount: s.configurationCount,
      hasPermission: s.hasPermission,
      isInputDevice: s.isInputDevice,
      inputSources: s.inputSources,
      vendorName: view.vendorName,
      productNameResolved: view.productName,
      manufacturerNameRaw: s.manufacturerName,
      productNameRaw: s.productName,
      serialNumber: s.serialNumber,
      usbVersion: s.usbVersion,
      speed: s.speed,
      deviceId: s.deviceId,
      portNumber: s.portNumber,
    );

    await _upsert(entry);
  }

  Future<DeviceHistoryEntry?> removeById(String id) async {
    final current = state.asData?.value ?? await _loadFromPrefs();
    final idx = current.indexWhere((e) => e.id == id);
    if (idx == -1) return null;
    final removed = current[idx];
    final next = [...current]..removeAt(idx);
    state = AsyncValue.data(next);
    await _saveToPrefs(next);
    return removed;
  }

  Future<void> restore(DeviceHistoryEntry entry, {int? index}) async {
    final current = state.asData?.value ?? await _loadFromPrefs();
    final without = current.where((e) => e.id != entry.id).toList(growable: true);
    final i = (index == null) ? 0 : index.clamp(0, without.length);
    without.insert(i, entry);
    final capped = without.length <= _kHistoryMaxItems
        ? without
        : without.take(_kHistoryMaxItems).toList();
    state = AsyncValue.data(capped);
    await _saveToPrefs(capped);
  }

  Future<void> clearAll() async {
    state = const AsyncValue.data([]);
    await _saveToPrefs(const []);
  }

  String _makeStableIdFromSummary(UsbDeviceSummary s) {
    final serial = (s.serialNumber ?? '').trim();
    if (serial.isNotEmpty) {
      return 'vid:${s.vendorId}|pid:${s.productId}|sn:$serial';
    }
    final did = s.deviceId;
    if (did != null && did != 0) {
      return 'vid:${s.vendorId}|pid:${s.productId}|devId:$did|input:${s.isInputDevice}';
    }
    final dn = s.deviceName.trim();
    if (dn.isNotEmpty) {
      return 'path:$dn';
    }
    return 'vid:${s.vendorId}|pid:${s.productId}|cls:${s.deviceClass}|sub:${s.deviceSubclass}|pr:${s.deviceProtocol}|input:${s.isInputDevice}';
  }
}
