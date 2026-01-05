import 'package:meta/meta.dart';

@immutable
class DeviceHistoryEntry {
  const DeviceHistoryEntry({
    required this.id,
    required this.testedAt,
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.deviceClass,
    required this.deviceSubclass,
    required this.deviceProtocol,
    required this.interfaceCount,
    required this.configurationCount,
    required this.hasPermission,
    required this.isInputDevice,
    this.inputSources,
    this.vendorName,
    this.productNameResolved,
    this.manufacturerNameRaw,
    this.productNameRaw,
    this.serialNumber,
    this.usbVersion,
    this.speed,
    this.deviceId,
    this.portNumber,
  });

  final String id;
  final DateTime testedAt;

  final String deviceName;

  final int vendorId;
  final int productId;

  final int deviceClass;
  final int deviceSubclass;
  final int deviceProtocol;

  final int interfaceCount;
  final int configurationCount;

  final bool hasPermission;

  final bool isInputDevice;
  final List<String>? inputSources;

  /// Resolved from usbids.sqlite when available.
  final String? vendorName;
  final String? productNameResolved;

  /// Raw strings as reported by Android (may be null / permission gated).
  final String? manufacturerNameRaw;
  final String? productNameRaw;
  final String? serialNumber;

  final String? usbVersion;
  final String? speed;

  final int? deviceId;
  final int? portNumber;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'testedAt': testedAt.toIso8601String(),
        'deviceName': deviceName,
        'vendorId': vendorId,
        'productId': productId,
        'deviceClass': deviceClass,
        'deviceSubclass': deviceSubclass,
        'deviceProtocol': deviceProtocol,
        'interfaceCount': interfaceCount,
        'configurationCount': configurationCount,
        'hasPermission': hasPermission,
        'isInputDevice': isInputDevice,
        'inputSources': inputSources,
        'vendorName': vendorName,
        'productNameResolved': productNameResolved,
        'manufacturerNameRaw': manufacturerNameRaw,
        'productNameRaw': productNameRaw,
        'serialNumber': serialNumber,
        'usbVersion': usbVersion,
        'speed': speed,
        'deviceId': deviceId,
        'portNumber': portNumber,
      };

  factory DeviceHistoryEntry.fromMap(Map<Object?, Object?> map) {
    final rawSources = map['inputSources'];
    return DeviceHistoryEntry(
      id: (map['id'] as String?) ?? '',
      testedAt: DateTime.tryParse((map['testedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deviceName: (map['deviceName'] as String?) ?? '',
      vendorId: (map['vendorId'] as int?) ?? 0,
      productId: (map['productId'] as int?) ?? 0,
      deviceClass: (map['deviceClass'] as int?) ?? 0,
      deviceSubclass: (map['deviceSubclass'] as int?) ?? 0,
      deviceProtocol: (map['deviceProtocol'] as int?) ?? 0,
      interfaceCount: (map['interfaceCount'] as int?) ?? 0,
      configurationCount: (map['configurationCount'] as int?) ?? 0,
      hasPermission: (map['hasPermission'] as bool?) ?? false,
      isInputDevice: (map['isInputDevice'] as bool?) ?? false,
      inputSources: rawSources is List
          ? rawSources.whereType<String>().toList(growable: false)
          : null,
      vendorName: map['vendorName'] as String?,
      productNameResolved: map['productNameResolved'] as String?,
      manufacturerNameRaw: map['manufacturerNameRaw'] as String?,
      productNameRaw: map['productNameRaw'] as String?,
      serialNumber: map['serialNumber'] as String?,
      usbVersion: map['usbVersion'] as String?,
      speed: map['speed'] as String?,
      deviceId: map['deviceId'] as int?,
      portNumber: map['portNumber'] as int?,
    );
  }

  DeviceHistoryEntry copyWith({
    DateTime? testedAt,
  }) {
    return DeviceHistoryEntry(
      id: id,
      testedAt: testedAt ?? this.testedAt,
      deviceName: deviceName,
      vendorId: vendorId,
      productId: productId,
      deviceClass: deviceClass,
      deviceSubclass: deviceSubclass,
      deviceProtocol: deviceProtocol,
      interfaceCount: interfaceCount,
      configurationCount: configurationCount,
      hasPermission: hasPermission,
      isInputDevice: isInputDevice,
      inputSources: inputSources,
      vendorName: vendorName,
      productNameResolved: productNameResolved,
      manufacturerNameRaw: manufacturerNameRaw,
      productNameRaw: productNameRaw,
      serialNumber: serialNumber,
      usbVersion: usbVersion,
      speed: speed,
      deviceId: deviceId,
      portNumber: portNumber,
    );
  }
}
