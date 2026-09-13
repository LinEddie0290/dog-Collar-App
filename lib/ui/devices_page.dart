import 'package:flutter/material.dart';

import '../data/ble_collar_data_source.dart';
import '../data/known_device.dart';
import '../l10n/app_strings.dart';
import '../l10n/error_text.dart';
import '../state/collar_link.dart';
import 'app_colors.dart';

/// 首輪を選ぶ画面。
///
/// **ここでは接続しない。** 接続の開始と停止は測定画面の中央ボタンだけが行う。
/// 操作の入口を2か所に置くと、片方でキャンセルしてももう片方の状態が残って
/// ボタンが固まる。実際にそれが起きたので、役割を分けた。
/// この画面は「どの首輪を使うか」「名前を変える」「登録を消す」用。
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.link});

  final CollarLink link;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await widget.link.loadKnown();
    if (!mounted) return;
    // 初めて開いたとき(登録ゼロ)は勝手に探し始める。ここに来た人は
    // 首輪を登録しに来たのであって、検索ボタンを探しに来たのではない。
    if (widget.link.known.isEmpty &&
        !widget.link.isConnected &&
        !widget.link.isScanning) {
      await widget.link.startScan();
    }
  }

  @override
  void dispose() {
    // 画面を出たらスキャンは止める。BLEスキャンは電池を食うし、
    // 裏で回り続けると接続時に邪魔になる。
    widget.link.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings s = AppStringsScope.of(context);
    return AnimatedBuilder(
      animation: widget.link,
      builder: (BuildContext context, Widget? _) {
        final CollarLink link = widget.link;
        final Set<String> knownIds =
            link.known.map((KnownDevice d) => d.remoteId).toSet();
        final List<CollarScanHit> fresh = link.discovered
            .where((CollarScanHit h) => !knownIds.contains(h.remoteId))
            .toList(growable: false);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            if (link.isConnected)
              _Banner(
                icon: Icons.bluetooth_connected,
                color: AppColors.connected,
                text: '${s.collarConnectedTo}　'
                    '${link.targetName ?? "PET-Sense"}',
              ),
            if (link.errorMessage != null && !link.isConnected)
              _Banner(
                icon: Icons.error_outline,
                color: AppColors.accent,
                text: errorText(s, link.errorMessage)!,
              ),
            Row(
              children: <Widget>[
                Text(s.registeredCollars,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const Spacer(),
                if (link.isScanning)
                  Row(
                    children: <Widget>[
                      const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: link.stopScan,
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.textFaint,
                            minimumSize: const Size(0, 32)),
                        child: Text(s.cancelAction,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  )
                else
                  TextButton.icon(
                    // 接続中はスキャンできない（首輪は同時1台のみ）。
                    onPressed: link.isConnected ? null : link.startScan,
                    icon: const Icon(Icons.search, size: 16),
                    label: Text(s.searchAction),
                    style:
                        TextButton.styleFrom(foregroundColor: AppColors.accent),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (link.known.isEmpty && !link.isScanning)
              _Info(text: s.noCollarsYet)
            else
              ...link.known.map((KnownDevice d) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _DeviceRow(
                      link: link,
                      s: s,
                      device: d,
                      rssi: _rssiOf(link, d.remoteId),
                    ),
                  )),
            if (fresh.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Text(s.newlyFound,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              ...fresh.map((CollarScanHit h) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _DeviceRow(
                      link: link,
                      s: s,
                      device: KnownDevice(
                        remoteId: h.remoteId,
                        name: h.name,
                        firstSeenAt: DateTime.now(),
                        lastSeenAt: DateTime.now(),
                      ),
                      rssi: h.rssi,
                      isNew: true,
                    ),
                  )),
            ],
            const SizedBox(height: 18),
            _NoteBox(s: s),
          ],
        );
      },
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.link,
    required this.s,
    required this.device,
    this.rssi,
    this.isNew = false,
  });

  final CollarLink link;
  final AppStrings s;
  final KnownDevice device;
  final int? rssi;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final bool selected = link.selectedRemoteId == device.remoteId;
    final bool connected =
        link.isConnected && link.targetRemoteId == device.remoteId;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 1.6 : 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            // タップは「使う首輪の選択」。接続はしない。
            // 選んだら測定画面に戻る。この画面に来る目的は選ぶことなので、
            // 選んだ直後に「次はどこを押すのか」で迷わせない。
            onTap: () {
              link.select(device.remoteId, device.displayName);
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            leading: Icon(
              connected
                  ? Icons.bluetooth_connected
                  : selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
              color: connected
                  ? AppColors.connected
                  : selected
                      ? AppColors.accent
                      : AppColors.textFaint,
              size: 21,
            ),
            title: Text(device.displayName,
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            subtitle: Text(
              <String>[
                device.shortId,
                if (rssi != null) '${s.signalStrength} ${rssi}dBm',
                if (!isNew && device.connectCount > 0)
                  '${s.connectTimes} ${device.connectCount}',
                if (!isNew && device.lastConnectedAt != null)
                  '${s.lastConnected} ${_short(device.lastConnectedAt!)}',
              ].join('　'),
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            trailing: Text(
              connected
                  ? s.collarConnectedTo
                  : selected
                      ? s.selectedLabel
                      : s.selectAction,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: connected
                      ? AppColors.connected
                      : selected
                          ? AppColors.accent
                          : AppColors.textSecondary),
            ),
          ),
          if (!isNew)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => _rename(context, s),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textFaint,
                        minimumSize: const Size(0, 32)),
                    child: Text(s.renameAction,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                  TextButton(
                    onPressed: () => link.forget(device.remoteId),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textFaint,
                        minimumSize: const Size(0, 32)),
                    child: Text(s.forgetAction,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, AppStrings s) async {
    final TextEditingController c =
        TextEditingController(text: device.nickname ?? '');
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(s.collarNameDialogTitle),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: s.collarNameHint),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.cancelAction)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(s.saveAction)),
        ],
      ),
    );
    if (name != null) {
      await link.rename(device.remoteId, name);
    }
  }
}

/// 直近のスキャンで見えていれば電波強度を返す。見えていなければ null。
/// package:collection の firstOrNull は import 依存なので使わない。
int? _rssiOf(CollarLink link, String remoteId) {
  for (final CollarScanHit h in link.discovered) {
    if (h.remoteId == remoteId) return h.rssi;
  }
  return null;
}

String _short(DateTime d) =>
    '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5, height: 1.6, color: AppColors.textSecondary)),
      );
}

class _NoteBox extends StatelessWidget {
  const _NoteBox({required this.s});
  final AppStrings s;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(s.goodToKnowTitle,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 7),
            ...<String>[
              s.noteOneClientOnly,
              s.noteKnownIsFast,
              s.noteNoBatteryYet,
            ].map((String t) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('•  $t',
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.6,
                          color: AppColors.textSecondary)),
                )),
          ],
        ),
      );
}
