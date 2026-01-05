import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/usb_ids_db.dart';
import 'models.dart';
import 'platform_usb_service.dart';
import 'usb_repository.dart';

final usbPlatformServiceProvider = Provider<UsbPlatformService>((ref) {
  return UsbPlatformService();
});

final usbIdsDbProvider = FutureProvider<UsbIdsDb>((ref) async {
  final db = await UsbIdsDb.open();
  ref.onDispose(db.close);
  return db;
});

final usbRepositoryProvider = Provider<UsbRepository>((ref) {
  final platform = ref.watch(usbPlatformServiceProvider);
  final db = ref.watch(usbIdsDbProvider).value;
  if (db == null) {
    throw StateError('USB IDs database not initialized yet.');
  }
  return UsbRepository(platform, db);
});

final usbEventsProvider = StreamProvider<UsbEvent>((ref) async* {
  await ref.watch(usbIdsDbProvider.future);
  final repo = ref.read(usbRepositoryProvider);
  yield* repo.events();
});
