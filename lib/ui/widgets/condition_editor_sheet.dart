import 'package:flutter/material.dart';

import '../../data/measurement_record.dart';
import '../../data/measurement_store.dart';
import '../../l10n/app_strings.dart';
import '../app_colors.dart';

/// 測定条件を選択式で記録するシート。
///
/// 自由文にすると後から比較できない — 2026-09-15、犬5件の実測を本人の
/// 説明が無いと解釈できなかった。選択式にして、あとで条件を揃えて比較
/// できるようにする。手で数えた正解も同じシートで入力する。これが無いと
/// どのセンサー・当て方が良いかを永久に検証できない。
class ConditionEditorSheet extends StatefulWidget {
  const ConditionEditorSheet(
      {super.key, required this.record, required this.store});

  final MeasurementRecord record;
  final MeasurementStore store;

  /// シートを開き、保存したら true を返す。キャンセルやそのまま閉じたら false。
  static Future<bool> show(
    BuildContext context, {
    required MeasurementRecord record,
    required MeasurementStore store,
  }) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext _) =>
          ConditionEditorSheet(record: record, store: store),
    );
    return saved ?? false;
  }

  @override
  State<ConditionEditorSheet> createState() => _ConditionEditorSheetState();
}

class _ConditionEditorSheetState extends State<ConditionEditorSheet> {
  String? _posture;
  bool? _panting;
  String? _activity;
  String? _position;
  String? _pressure;
  late final TextEditingController _refBpmCtrl;
  late final TextEditingController _noteCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final MeasurementRecord r = widget.record;
    _posture = r.posture;
    _panting = r.panting;
    _activity = r.recentActivity;
    _position = r.position;
    _pressure = r.pressure;
    _refBpmCtrl = TextEditingController(
        text: r.referenceBpm == null ? '' : r.referenceBpm!.toStringAsFixed(0));
    _noteCtrl = TextEditingController(text: r.note ?? '');
  }

  @override
  void dispose() {
    _refBpmCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final double? refBpm = double.tryParse(_refBpmCtrl.text.trim());
    final String note = _noteCtrl.text.trim();
    try {
      await widget.store.annotate(
        widget.record.id,
        posture: _posture,
        panting: _panting,
        recentActivity: _activity,
        position: _position,
        pressure: _pressure,
        referenceBpm: refBpm,
        note: note.isEmpty ? widget.record.note : note,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings s = AppStringsScope.of(context);
    return SafeArea(
      child: Padding(
        // キーボードが出たぶんだけ持ち上げる。
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(s.conditionEditorTitle,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                _SectionLabel(s.conditionHealthSection),
                const SizedBox(height: 8),
                _ChipRow<String>(
                  label: s.postureLabel,
                  value: _posture,
                  options: <(String, String)>[
                    (s.postureCarried, s.postureCarried),
                    (s.postureStanding, s.postureStanding),
                    (s.postureSitting, s.postureSitting),
                    (s.postureLyingDown, s.postureLyingDown),
                    (s.postureOnBack, s.postureOnBack),
                  ],
                  onChanged: (String? v) => setState(() => _posture = v),
                ),
                const SizedBox(height: 12),
                _BoolChipRow(
                  label: s.pantingLabel,
                  value: _panting,
                  yesLabel: s.pantingYes,
                  noLabel: s.pantingNo,
                  unknownLabel: s.pantingUnknown,
                  onChanged: (bool? v) => setState(() => _panting = v),
                ),
                const SizedBox(height: 12),
                _ChipRow<String>(
                  label: s.recentActivityLabel,
                  value: _activity,
                  options: <(String, String)>[
                    (s.activityResting, s.activityResting),
                    (s.activityWalking, s.activityWalking),
                    (s.activityActive, s.activityActive),
                    (s.activitySleeping, s.activitySleeping),
                    (s.activityUnknown, s.activityUnknown),
                  ],
                  onChanged: (String? v) => setState(() => _activity = v),
                ),
                const SizedBox(height: 14),
                Text(s.referenceBpmLabel,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                TextField(
                  controller: _refBpmCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  decoration: InputDecoration(
                    hintText: s.referenceBpmHint,
                    hintStyle: const TextStyle(
                        fontSize: 12, color: AppColors.textFaint),
                    isDense: true,
                    suffixText: 'bpm',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionLabel(s.conditionSensorSection),
                const SizedBox(height: 8),
                _ChipRow<String>(
                  label: s.positionLabel,
                  value: _position,
                  options: <(String, String)>[
                    (s.positionNeck, s.positionNeck),
                    (s.positionChest, s.positionChest),
                    (s.positionThigh, s.positionThigh),
                    (s.positionOther, s.positionOther),
                  ],
                  onChanged: (String? v) => setState(() => _position = v),
                ),
                const SizedBox(height: 12),
                _ChipRow<String>(
                  label: s.pressureLabel,
                  value: _pressure,
                  options: <(String, String)>[
                    (s.pressureFirm, s.pressureFirm),
                    (s.pressureMedium, s.pressureMedium),
                    (s.pressurePlaced, s.pressurePlaced),
                  ],
                  onChanged: (String? v) => setState(() => _pressure = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: s.conditionNoteHint,
                    hintStyle: const TextStyle(
                        fontSize: 12, color: AppColors.textFaint),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(s.saveAction,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textFaint,
          letterSpacing: 0.2));
}

/// 単一選択のチップ列。もう一度押すと選択解除できりわ(「わからない」を
/// 選び直す手間を避けるため — 触らなければ null のまま送られる)。
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final (T code, String text) in options)
                ChoiceChip(
                  label: Text(text, style: const TextStyle(fontSize: 12.5)),
                  selected: value == code,
                  onSelected: (bool selected) =>
                      onChanged(selected ? code : null),
                  selectedColor: AppColors.accent.withValues(alpha: 0.16),
                  backgroundColor: AppColors.background,
                  side: BorderSide(
                      color:
                          value == code ? AppColors.accent : AppColors.border),
                  labelStyle: TextStyle(
                      color: value == code
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      fontWeight:
                          value == code ? FontWeight.w800 : FontWeight.w500),
                ),
            ],
          ),
        ],
      );
}

/// panting 専用。3択(している/していない/わからない)を bool? に対応づける。
class _BoolChipRow extends StatelessWidget {
  const _BoolChipRow({
    required this.label,
    required this.value,
    required this.yesLabel,
    required this.noLabel,
    required this.unknownLabel,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final String yesLabel;
  final String noLabel;
  final String unknownLabel;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    // わからない、を「未選択」と区別できるよう、選択済みかどうかを別に持つ。
    // Sentinel: true=はい, false=いいえ, null=わからない。押されるまでは
    // どれも選択済みでない見た目にする(record 側の既存値がある場合を除く)。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _boolChip(yesLabel, true),
            _boolChip(noLabel, false),
            _boolChip(unknownLabel, null),
          ],
        ),
      ],
    );
  }

  Widget _boolChip(String text, bool? code) {
    final bool selected = value == code;
    return ChoiceChip(
      label: Text(text, style: const TextStyle(fontSize: 12.5)),
      selected: selected,
      onSelected: (bool s) => onChanged(s ? code : null),
      selectedColor: AppColors.accent.withValues(alpha: 0.16),
      backgroundColor: AppColors.background,
      side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
      labelStyle: TextStyle(
          color: selected ? AppColors.accent : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500),
    );
  }
}
