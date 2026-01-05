import '../db/usb_ids_db.dart';
import 'models.dart';
import 'platform_usb_service.dart';

class UsbDeviceListItem {
  UsbDeviceListItem({
    required this.device,
    required this.vendorName,
    required this.productName,
    required this.deviceClassName,
  });

  final UsbDeviceSummary device;
  final String? vendorName;
  final String? productName;
  final String? deviceClassName;
}

class UsbDeviceDetailViewData {
  UsbDeviceDetailViewData({
    required this.details,
    required this.vendorName,
    required this.productName,
    required this.deviceClassName,
    required this.deviceSubclassName,
    required this.deviceProtocolName,
    required this.interfaceClassNames,
  });

  final UsbDeviceDetails details;
  final String? vendorName;
  final String? productName;

  final String? deviceClassName;
  final String? deviceSubclassName;
  final String? deviceProtocolName;

  /// Parallel list to interfaces: resolved class/subclass/protocol names.
  final List<({String? className, String? subclassName, String? protocolName})> interfaceClassNames;
}

class UsbRepository {
  UsbRepository(this._platform, this._db);

  final UsbPlatformService _platform;
  final UsbIdsDb _db;

  Future<List<UsbDeviceListItem>> listDevicesEnriched() async {
    final devices = await _platform.listDevices();

    final List<UsbDeviceListItem> out = [];
    for (final d in devices) {
      final v = await _db.vendorName(d.vendorId);
      final p = await _db.productName(d.vendorId, d.productId);
      final c = await _db.usbClassName(d.deviceClass);
      out.add(UsbDeviceListItem(
        device: d,
        vendorName: v,
        productName: p,
        deviceClassName: c,
      ));
    }
    return out;
  }

  Future<bool> requestPermission(String deviceName) => _platform.requestPermission(deviceName);

  Future<UsbDeviceDetailViewData> getDeviceDetailsEnriched(String deviceName) async {
    final details = await _platform.getDeviceDetails(deviceName);
    final s = details.summary;

    final vendorName = await _db.vendorName(s.vendorId);
    final productName = await _db.productName(s.vendorId, s.productId);

    final deviceClassName = await _db.usbClassName(s.deviceClass);
    final deviceSubclassName = await _db.usbSubclassName(s.deviceClass, s.deviceSubclass);
    final deviceProtocolName = await _db.usbProtocolName(s.deviceClass, s.deviceSubclass, s.deviceProtocol);

    final ifaceNames = <({String? className, String? subclassName, String? protocolName})>[];
    for (final i in details.interfaces) {
      final c = await _db.usbClassName(i.interfaceClass);
      final sc = await _db.usbSubclassName(i.interfaceClass, i.interfaceSubclass);
      final pr = await _db.usbProtocolName(i.interfaceClass, i.interfaceSubclass, i.interfaceProtocol);
      ifaceNames.add((className: c, subclassName: sc, protocolName: pr));
    }

    return UsbDeviceDetailViewData(
      details: details,
      vendorName: vendorName,
      productName: productName,
      deviceClassName: deviceClassName,
      deviceSubclassName: deviceSubclassName,
      deviceProtocolName: deviceProtocolName,
      interfaceClassNames: ifaceNames,
    );
  }

  Stream<UsbEvent> events() => _platform.events();
}
