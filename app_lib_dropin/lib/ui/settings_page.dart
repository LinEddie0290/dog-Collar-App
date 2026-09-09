import 'package:collar_data/collar_data.dart';
import 'package:flutter/material.dart';

import '../state/collar_controller.dart';
import 'app_colors.dart';
import 'conn_status_ja.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final CollarController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.controller.url);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final CollarController controller = widget.controller;
        final bool busy = controller.status == ConnStatus.connecting ||
            controller.status == ConnStatus.reconnecting;

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              Text(
                '設定',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('接続'),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  _SettingsRow(
                    child: Row(
                      children: <Widget>[
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'アプリ内モックを使う',
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '首輪が無くても動作を確認できます',
                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: controller.useMock,
                          activeTrackColor: AppColors.accent,
                          onChanged: controller.isConnected
                              ? null
                              : controller.setUseMock,
                        ),
                      ],
                    ),
                  ),
                  _SettingsRow(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '接続先 URL',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _urlController,
                          enabled: !controller.useMock && !controller.isConnected,
                          style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            hintText: 'ws://192.168.x.x:8080/ws',
                          ),
                          onChanged: controller.setUrl,
                        ),
                      ],
                    ),
                  ),
                  _SettingsRow(
                    last: true,
                    child: Row(
                      children: <Widget>[
                        const Expanded(
                          child: Text('状態', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                        _StatusChip(status: controller.status),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: (controller.isConnected || busy)
                          ? null
                          : () => controller.connect(),
                      child: const Text('接続する'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: (!controller.isConnected && !busy)
                          ? null
                          : () => controller.disconnect(),
                      child: const Text('切断する'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('首輪'),
              const SizedBox(height: 8),
              const _SectionCard(
                children: <Widget>[
                  _SettingsRow(child: _KeyValueRow(label: '名前', value: 'モモの首輪')),
                  _SettingsRow(child: _KeyValueRow(label: 'バッテリー', value: '--')),
                  _SettingsRow(last: true, child: _KeyValueRow(label: 'ファームウェア', value: '--')),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('データ'),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  const _SettingsRow(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('保存先', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text(
                          '端末内に日付ごとに保存されます',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _SettingsRow(
                    last: true,
                    child: Row(
                      children: const <Widget>[
                        Icon(Icons.file_download_outlined, size: 16, color: AppColors.textFaint),
                        SizedBox(width: 10),
                        Text(
                          '記録をエクスポート(準備中)',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Center(
                child: Column(
                  children: <Widget>[
                    Text('首輪アプリ', style: TextStyle(fontSize: 11.5, color: AppColors.textFaint)),
                    SizedBox(height: 2),
                    Text('version 0.1.0', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.child, this.last = false});

  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: child,
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
        Text(value, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ConnStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color =
        status == ConnStatus.connected ? AppColors.connected : AppColors.textFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          status.labelJa,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
