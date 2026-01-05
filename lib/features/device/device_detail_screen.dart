import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/key_value_row.dart';
import '../../core/widgets/section_card.dart';
import '../../data/usb/models.dart';
import '../../data/usb/providers.dart';
import '../../data/usb/usb_repository.dart';
import '../history/controllers/device_history_controller.dart';
import 'controllers/device_detail_controller.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({super.key, required this.deviceName});
  static const routeName = 'device';

  final String deviceName;

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  @override
  void initState() {
    super.initState();

    void recordIfReady(AsyncValue<UsbDeviceDetailViewData> v) {
      final data = v.asData?.value;
      if (data != null) {
        ref.read(deviceHistoryControllerProvider.notifier).recordFromView(data);
      }
    }

    recordIfReady(ref.read(deviceDetailControllerProvider(widget.deviceName)));

    ref.listen<AsyncValue<UsbDeviceDetailViewData>>(
      deviceDetailControllerProvider(widget.deviceName),
      (prev, next) => recordIfReady(next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deviceDetailControllerProvider(widget.deviceName));
    return Scaffold(
      appBar: AppBar(title: const Text('Device info')),
      body: SafeArea(
        child: async.when(
          data: (data) => _DeviceDetailBody(view: data),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => _ErrorBody(error: e.toString()),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.error_outline_rounded, size: 48),
        const SizedBox(height: 12),
        Text('Unable to read device details.', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(error),
      ],
    );
  }
}

class _DeviceDetailBody extends StatelessWidget {
  const _DeviceDetailBody({required this.view});
  final UsbDeviceDetailViewData view;

  @override
  Widget build(BuildContext context) {
    final s = view.details.summary;
    final theme = Theme.of(context);
    final title = view.productName ?? s.productName ?? (s.isInputDevice ? 'Input device' : 'USB Device');
    final subtitle = view.vendorName ?? s.manufacturerName ?? 'Unknown vendor';
    final isInput = s.isInputDevice;
    final needsPermission = !isInput && !s.hasPermission;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    isInput ? Icons.keyboard_alt_rounded : Icons.usb_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (needsPermission) _PermissionBanner(deviceName: s.deviceName),
        if (needsPermission) const SizedBox(height: 12),
        _identitySection(context),
        const SizedBox(height: 12),
        _usbSpecSection(context),
        const SizedBox(height: 12),
        _locationSection(context),
        const SizedBox(height: 12),
        if (!isInput) ...[
          _descriptorSection(context),
          const SizedBox(height: 12),
          _powerSection(context),
          const SizedBox(height: 12),
          _configurationsSection(context),
          const SizedBox(height: 12),
          _interfacesSection(context),
        ] else ...[
          _inputDeviceSection(context),
        ],
      ],
    );
  }

  Widget _identitySection(BuildContext context) {
    final s = view.details.summary;
    final vendor = view.vendorName ?? s.manufacturerName;
    final product = view.productName ?? s.productName;
    return SectionCard(
      title: 'Identity',
      subtitle: 'IDs, vendor/product strings',
      leading: const Icon(Icons.badge_outlined),
      child: Column(
        children: [
          KeyValueRow(label: 'Vendor ID', value: Fmt.decAndHex16(s.vendorId)),
          KeyValueRow(label: 'Product ID', value: Fmt.decAndHex16(s.productId)),
          KeyValueRow(label: 'Vendor', value: Fmt.formatNullable(vendor)),
          KeyValueRow(label: 'Product', value: Fmt.formatNullable(product)),
          KeyValueRow(label: 'Serial', value: Fmt.formatNullable(s.serialNumber)),
        ],
      ),
    );
  }

  Widget _usbSpecSection(BuildContext context) {
    final s = view.details.summary;
    return SectionCard(
      title: 'USB specification',
      subtitle: 'Version, speed, class/protocol',
      leading: const Icon(Icons.tune_rounded),
      child: Column(
        children: [
          KeyValueRow(label: 'USB version', value: Fmt.formatNullable(s.usbVersion)),
          KeyValueRow(label: 'Speed', value: Fmt.speedLabel(s.speed)),
          KeyValueRow(label: 'Device class', value: _joinNameAndIds(view.deviceClassName, s.deviceClass)),
          KeyValueRow(label: 'Subclass', value: _joinNameAndIds(view.deviceSubclassName, s.deviceSubclass)),
          KeyValueRow(label: 'Protocol', value: _joinNameAndIds(view.deviceProtocolName, s.deviceProtocol)),
          KeyValueRow(label: 'Interfaces', value: '${s.interfaceCount}'),
          KeyValueRow(label: 'Configurations', value: '${s.configurationCount}'),
        ],
      ),
    );
  }

  Widget _locationSection(BuildContext context) {
    final s = view.details.summary;
    return SectionCard(
      title: 'Location',
      subtitle: 'Android identifiers and bus hints',
      leading: const Icon(Icons.pin_drop_outlined),
      child: Column(
        children: [
          KeyValueRow(label: 'Device path', value: s.deviceName),
          KeyValueRow(label: 'Android deviceId', value: s.deviceId == null ? 'Unknown' : '${s.deviceId}'),
          KeyValueRow(label: 'Port number', value: s.portNumber == null ? 'Unknown' : '${s.portNumber}'),
          KeyValueRow(
            label: 'Type',
            value: s.isInputDevice ? 'Input device (keyboard/mouse via InputManager)' : 'USB device (UsbManager)',
            allowCopy: false,
          ),
        ],
      ),
    );
  }

  Widget _descriptorSection(BuildContext context) {
    final d = view.details.deviceDescriptor;
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Device descriptor',
      subtitle: 'Raw USB descriptor fields',
      leading: const Icon(Icons.article_outlined),
      child: d == null
          ? Text(
              'Grant permission to parse raw descriptors (bcdUSB, device release, packet sizes).',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : _ExpandableBlock(
              title: 'Show descriptor fields',
              initiallyExpanded: true,
              child: Column(
                children: [
                  KeyValueRow(label: 'USB spec (bcdUSB)', value: d.usbVersion ?? 'Unknown'),
                  KeyValueRow(label: 'Device release (bcdDevice)', value: d.deviceRelease ?? 'Unknown'),
                  KeyValueRow(label: 'EP0 max packet', value: d.maxPacketSize0 == null ? 'Unknown' : '${d.maxPacketSize0}'),
                  KeyValueRow(label: 'Num configurations', value: d.numConfigurations == null ? 'Unknown' : '${d.numConfigurations}'),
                  KeyValueRow(label: 'iManufacturer', value: d.iManufacturer == null ? 'Unknown' : '${d.iManufacturer}'),
                  KeyValueRow(label: 'iProduct', value: d.iProduct == null ? 'Unknown' : '${d.iProduct}'),
                  KeyValueRow(label: 'iSerialNumber', value: d.iSerialNumber == null ? 'Unknown' : '${d.iSerialNumber}'),
                ],
              ),
            ),
    );
  }

  Widget _powerSection(BuildContext context) {
    final s = view.details.summary;
    final theme = Theme.of(context);
    final maxPower = s.maxPowerMa == null ? 'Unknown' : '${s.maxPowerMa} mA';
    return SectionCard(
      title: 'Power',
      subtitle: 'Configuration power budget',
      leading: const Icon(Icons.bolt_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyValueRow(label: 'Max power (config 0)', value: maxPower),
          const SizedBox(height: 8),
          Text(
            'Note: power values depend on what the device reports. Some devices omit or misreport this field.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _configurationsSection(BuildContext context) {
    final cfgs = view.details.configurations;
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Configurations',
      subtitle: 'All reported USB configurations',
      leading: const Icon(Icons.layers_outlined),
      child: cfgs.isEmpty
          ? Text(
              'No configurations reported (or not accessible).',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : Column(
              children: [
                for (int i = 0; i < cfgs.length; i++) ...[
                  if (i > 0) const Divider(height: 24),
                  _ConfigBlock(cfg: cfgs[i], index: i),
                ],
              ],
            ),
    );
  }

  Widget _interfacesSection(BuildContext context) {
    final theme = Theme.of(context);
    final ifaces = view.details.interfaces;
    return SectionCard(
      title: 'Interfaces & endpoints',
      subtitle: 'Parsed interface and endpoint descriptors',
      leading: const Icon(Icons.account_tree_outlined),
      child: ifaces.isEmpty
          ? Text(
              'No interfaces reported.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : Column(
              children: [
                for (int idx = 0; idx < ifaces.length; idx++) ...[
                  if (idx > 0) const Divider(height: 24),
                  _InterfaceBlock(
                    index: idx,
                    iface: ifaces[idx],
                    resolved: view.interfaceClassNames.length > idx ? view.interfaceClassNames[idx] : null,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _inputDeviceSection(BuildContext context) {
    final theme = Theme.of(context);
    final input = view.details.input;
    final s = view.details.summary;
    return SectionCard(
      title: 'Input device',
      subtitle: 'Keyboard/mouse info from InputManager',
      leading: const Icon(Icons.keyboard_alt_outlined),
      child: input == null
          ? Text(
              'No input details available.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : Column(
              children: [
                KeyValueRow(label: 'Name', value: Fmt.formatNullable(input.name)),
                KeyValueRow(label: 'Descriptor', value: Fmt.formatNullable(input.descriptor)),
                KeyValueRow(label: 'External', value: input.isExternal ? 'Yes' : 'No'),
                KeyValueRow(label: 'VID', value: Fmt.decAndHex16(s.vendorId)),
                KeyValueRow(label: 'PID', value: Fmt.decAndHex16(s.productId)),
                KeyValueRow(label: 'Sources', value: input.sources.isEmpty ? 'Unknown' : input.sources.join(', ')),
                KeyValueRow(label: 'Keyboard type', value: '${input.keyboardType}'),
                KeyValueRow(label: 'Motion ranges', value: '${input.motionRanges.length}'),
                if (input.motionRanges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ExpandableBlock(
                    title: 'Show motion ranges',
                    child: Column(
                      children: [
                        for (final r in input.motionRanges.take(16)) ...[
                          KeyValueRow(
                            label: Fmt.axisLabel(r.axis),
                            value:
                                '${r.min.toStringAsFixed(2)} → ${r.max.toStringAsFixed(2)} (res ${r.resolution.toStringAsFixed(2)})',
                          ),
                        ],
                        if (input.motionRanges.length > 16)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Showing first 16 ranges.',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _joinNameAndIds(String? name, int id) {
    final n = (name == null || name.trim().isEmpty) ? 'Unknown' : name;
    return '$n (${Fmt.decAndHex8(id)})';
  }
}

class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner({required this.deviceName});
  final String deviceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_rounded, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Permission required',
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'To read strings (manufacturer/product/serial) and parse raw descriptors, Android requires per-device permission.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () async {
                  await ref.read(usbIdsDbProvider.future);
                  final repo = ref.read(usbRepositoryProvider);
                  final ok = await repo.requestPermission(deviceName);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Permission granted' : 'Permission not granted')),
                  );
                  if (ok) {
                    ref.invalidate(deviceDetailControllerProvider(deviceName));
                  }
                },
                icon: const Icon(Icons.vpn_key_rounded),
                label: const Text('Grant permission'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigBlock extends StatelessWidget {
  const _ConfigBlock({required this.cfg, required this.index});
  final UsbConfigurationInfo cfg;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxPower = cfg.maxPowerMa == null ? 'Unknown' : '${cfg.maxPowerMa} mA';
    final attrsHex = Fmt.decAndHex8(cfg.attributes);
    final attrsLabel = Fmt.usbConfigAttributesLabel(cfg.attributes);

    return _ExpandableBlock(
      title: 'Configuration ${cfg.id}${(cfg.name?.trim().isNotEmpty ?? false) ? ' — ${cfg.name}' : ''}',
      initiallyExpanded: index == 0,
      child: Column(
        children: [
          KeyValueRow(label: 'Name', value: Fmt.formatNullable(cfg.name)),
          KeyValueRow(label: 'Attributes', value: '$attrsHex • $attrsLabel'),
          KeyValueRow(label: 'Max power', value: maxPower),
          KeyValueRow(label: 'Interfaces', value: '${cfg.interfaceCount}'),
          if (cfg.interfaces.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Interfaces (summary)',
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            for (final i in cfg.interfaces.take(8)) ...[
              KeyValueRow(
                label: 'IF ${i.id}',
                value: 'Class ${Fmt.decAndHex8(i.interfaceClass)} • EP ${i.endpointCount}',
                allowCopy: false,
              ),
            ],
            if (cfg.interfaces.length > 8)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Showing first 8 interfaces.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _InterfaceBlock extends StatelessWidget {
  const _InterfaceBlock({
    required this.index,
    required this.iface,
    required this.resolved,
  });

  final int index;
  final UsbInterfaceInfo iface;
  final ({String? className, String? subclassName, String? protocolName})? resolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final classId = iface.interfaceClass;
    final subclassId = iface.interfaceSubclass;
    final protocolId = iface.interfaceProtocol;

    final className = resolved?.className;
    final subclassName = resolved?.subclassName;
    final protocolName = resolved?.protocolName;

    String join(String? n, int id) => '${(n == null || n.trim().isEmpty) ? 'Unknown' : n} (${Fmt.decAndHex8(id)})';

    return _ExpandableBlock(
      title: 'Interface ${iface.id} • ${join(className, classId)}',
      initiallyExpanded: index == 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iface.name != null && iface.name!.trim().isNotEmpty) KeyValueRow(label: 'Name', value: iface.name!),
          KeyValueRow(label: 'Alt setting', value: '${iface.alternateSetting}'),
          KeyValueRow(label: 'Class', value: join(className, classId)),
          KeyValueRow(label: 'Subclass', value: join(subclassName, subclassId)),
          KeyValueRow(label: 'Protocol', value: join(protocolName, protocolId)),
          const SizedBox(height: 10),
          Text(
            'Endpoints (${iface.endpointCount})',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (iface.endpoints.isEmpty)
            Text(
              'No endpoints',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Column(
              children: [
                for (final ep in iface.endpoints) ...[
                  _EndpointTile(ep: ep),
                  const SizedBox(height: 8),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _EndpointTile extends StatelessWidget {
  const _EndpointTile({required this.ep});
  final UsbEndpointInfo ep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dir = ep.direction;
    final type = ep.type;

    IconData icon;
    if (type.toLowerCase().contains('interrupt')) {
      icon = Icons.flash_on_rounded;
    } else if (type.toLowerCase().contains('bulk')) {
      icon = Icons.swap_horiz_rounded;
    } else if (type.toLowerCase().contains('isochronous')) {
      icon = Icons.av_timer_rounded;
    } else {
      icon = Icons.circle_outlined;
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$type • $dir', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Addr ${Fmt.decAndHex8(ep.address)} • EP# ${ep.number} • Attr ${Fmt.decAndHex8(ep.attributes)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('MaxPkt ${ep.maxPacketSize}', style: theme.textTheme.labelMedium),
                Text(
                  'Interval ${ep.interval}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableBlock extends StatelessWidget {
  const _ExpandableBlock({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        initiallyExpanded: initiallyExpanded,
        title: Text(title, style: theme.textTheme.titleMedium),
        children: [child],
      ),
    );
  }
}
