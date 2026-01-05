import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/usb/providers.dart';
import '../../../data/usb/usb_repository.dart';

final deviceDetailControllerProvider =
    FutureProvider.autoDispose.family<UsbDeviceDetailViewData, String>(
  (ref, deviceName) async {
    await ref.watch(usbIdsDbProvider.future);
    final repo = ref.read(usbRepositoryProvider);
    return repo.getDeviceDetailsEnriched(deviceName);
  },
);
