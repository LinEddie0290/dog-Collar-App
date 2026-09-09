import 'package:collar_data/collar_data.dart';
import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../state/collar_controller.dart';
import '../state/locale_controller.dart';
import 'app_colors.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.localeController,
  });

  final CollarController controller;
  final LocaleController localeController;

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
    final AppStrings strings = AppStringsScope.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[widget.controller, widget.localeController]),
      builder: (BuildContext context, Widget? _) {
        final CollarController controller = widget.controller;
        final bool busy = controller.status == ConnStatus.connecting ||
            controller.status == ConnStatus.reconnecting;

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              Text(
                strings.settingsTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
              ),
              const SizedBox(height: 20),
              _SectionLabel(strings.connectionSection),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  _SettingsRow(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                strings.useMockToggleTitle,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                strings.useMockToggleSubtitle,
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
                        Text(
                          strings.urlFieldLabel,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
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
                        Expanded(
                          child: Text(strings.statusLabel, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                        _StatusChip(status: controller.status, strings: strings),
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
                      child: Text(strings.connectButton),
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
                      child: Text(strings.disconnectButton),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(strings.languageSection),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  for (final AppLanguage lang in AppLanguage.values)
                    _SettingsRow(
                      last: lang == AppLanguage.values.last,
                      child: InkWell(
                        onTap: () => widget.localeController.setLanguage(lang),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                lang.nativeName,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (lang == widget.localeController.language)
                              const Icon(Icons.check, size: 18, color: AppColors.accent),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(strings.collarSection),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  _SettingsRow(child: _KeyValueRow(label: strings.nameLabel, value: strings.collarNameValue)),
                  _SettingsRow(child: _KeyValueRow(label: strings.batteryLabel, value: '--')),
                  _SettingsRow(last: true, child: _KeyValueRow(label: strings.firmwareLabel, value: '--')),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(strings.dataSection),
              const SizedBox(height: 8),
              _SectionCard(
                children: <Widget>[
                  _SettingsRow(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(strings.storageLocationLabel, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          strings.storageLocationDesc,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _SettingsRow(
                    last: true,
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.file_download_outlined, size: 16, color: AppColors.textFaint),
                        const SizedBox(width: 10),
                        Text(
                          strings.exportRecordsLabel,
                          style: const TextStyle(
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
              Center(
                child: Column(
                  children: <Widget>[
                    Text(strings.appTitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint)),
                    const SizedBox(height: 2),
                    const Text('version 0.1.0', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
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
  const _StatusChip({required this.status, required this.strings});

  final ConnStatus status;
  final AppStrings strings;

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
          strings.connStatusLabel(status),
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
