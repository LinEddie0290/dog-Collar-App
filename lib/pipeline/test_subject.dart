/// T34-E：試験の犬の情報（試験の記録の頭に入れる）。
library;

/// 首輪の位置（collar-pipeline の meta の placement と同じ値）。
const Map<String, String> collarPositions = <String, String>{
  'neck_ventral': '喉咙下面（前）',
  'neck_lateral': '脖子侧面',
  'neck_dorsal': '脖子后面（背）',
};

class TestSubject {
  const TestSubject({
    this.name = '',
    this.breed = '',
    this.weightKg,
    this.position = 'neck_ventral',
    this.note = '',
  });

  final String name;
  final String breed;
  final double? weightKg;
  final String position;
  final String note;

  bool get isEmpty => name.isEmpty && breed.isEmpty && weightKg == null && note.isEmpty;

  /// collar-pipeline の dog_id（名前がなければ 'app_dog'）。
  String get dogId => name.isEmpty ? 'app_dog' : name;

  String get summary {
    if (isEmpty) return '还没填';
    final List<String> p = <String>[
      if (name.isNotEmpty) name,
      if (breed.isNotEmpty) breed,
      if (weightKg != null) '${weightKg!.toStringAsFixed(1)} kg',
      collarPositions[position] ?? position,
    ];
    return p.join('・') + (note.isEmpty ? '' : '　（$note）');
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'breed': breed,
        'weight_kg': weightKg,
        'position': position,
        'note': note,
      };

  static TestSubject fromJson(Map<String, dynamic> j) => TestSubject(
        name: j['name'] as String? ?? '',
        breed: j['breed'] as String? ?? '',
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        position: j['position'] as String? ?? 'neck_ventral',
        note: j['note'] as String? ?? '',
      );
}
