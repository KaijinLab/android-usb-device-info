import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'core/usb/usb_event_coordinator.dart';
import 'data/db/usb_ids_update_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: UsbDevInfoApp()));
}

class UsbDevInfoApp extends ConsumerWidget {
  const UsbDevInfoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start side-effect coordinators (USB navigation + optional auto-check).
    ref.watch(usbEventCoordinatorProvider);
    ref.watch(usbIdsAutoCheckCoordinatorProvider);

    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeControllerProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'USBDevInfo',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
