/// T35：六大板块（《犬类健康・六类综合金字塔》）と、その中の項目の一覧。
///
/// 項目は「功能完成度表_2026-11-04」と同じ。心理の吠叫・低吼は爱迪の声のモジュール（金字塔にある）。
/// [HealthItem.real] は「今のアプリで本物のデータが出る」もの。それ以外は示例（偽のデータ）で出す（D-051 D2）。
/// 挠・持续舔舐・发抖は CNN v2（T35）で本物になったが、模擬で学んだクラスなので [HealthItem.trial]（试用）。
/// 文言は中国語だけ（D-051 D6）。
library;

/// 六大板块。並びはホームの泡の並び（上から時計回り）。
enum Board { exercise, sleep, physio, skin, mind, diet }

class HealthItem {
  const HealthItem(this.id, this.name, {this.real = false, this.trial = false});

  final String id;
  final String name;

  /// 今のアプリで本物のデータが出るか（出ないものは示例）。
  final bool real;

  /// 本物のデータだが「试用」（模擬の波形で学んだ CNN v2 のクラス。本物の犬でまだ確かめていない、D-005）。
  final bool trial;
}

class BoardInfo {
  const BoardInfo(this.board, this.name, this.lead, this.items);

  final Board board;
  final String name;

  /// ホームの泡に出す項目の id。
  final String lead;
  final List<HealthItem> items;
}

const List<BoardInfo> boardInfos = <BoardInfo>[
  BoardInfo(Board.exercise, '运动', 'activity', <HealthItem>[
    HealthItem('activity', '运动量（静止・走・跑）', real: true),
    HealthItem('active_rest', '活动与休息（一天的带）', real: true),
    HealthItem('jump', '起身・跳上跳下（关节）'),
    HealthItem('limp', '跛行（腿受伤）'),
    HealthItem('car', '坐车和散步的区分'),
  ]),
  BoardInfo(Board.sleep, '睡眠', 'sleep_time', <HealthItem>[
    HealthItem('sleep_time', '睡眠时长・区间・中断', real: true),
    HealthItem('sleep_rr', '睡觉时的呼吸（呼吸急促）', real: true),
    HealthItem('sleep_restless', '睡眠不安稳（翻身・起身）'),
  ]),
  BoardInfo(Board.physio, '生理', 'rest_hr', <HealthItem>[
    HealthItem('rest_hr', '安静时心率', real: true),
    HealthItem('rr', '呼吸数', real: true),
    HealthItem('ecg_like', '像心电图的波形', real: true),
    HealthItem('temp', '体温（发烧・下降）'),
    HealthItem('tremble', '发抖', real: true, trial: true),
    HealthItem('recovery', '运动后的恢复'),
    HealthItem('excretion', '排尿・排便'),
  ]),
  BoardInfo(Board.skin, '皮肤', 'scratch', <HealthItem>[
    HealthItem('scratch', '挠（耳朵・身体）', real: true, trial: true),
    HealthItem('lick', '持续舔舐', real: true, trial: true),
    HealthItem('shake', '甩身体'),
    HealthItem('rub', '蹭擦'),
  ]),
  BoardInfo(Board.mind, '心理', 'bark', <HealthItem>[
    HealthItem('bark', '吠叫'),
    HealthItem('growl', '低吼'),
    HealthItem('pacing', '来回走动（分离焦虑）'),
  ]),
  BoardInfo(Board.diet, '饮食', 'drink', <HealthItem>[
    HealthItem('eat', '进食'),
    HealthItem('drink', '饮水'),
    HealthItem('retch', '干呕・呕吐・噎住'),
  ]),
];

BoardInfo boardInfo(Board b) => boardInfos.firstWhere((BoardInfo i) => i.board == b);

/// id → 項目（なければ例外）。
HealthItem healthItem(String id) =>
    boardInfos.expand((BoardInfo b) => b.items).firstWhere((HealthItem i) => i.id == id);

/// 項目の板块。
Board boardOfItem(String id) =>
    boardInfos.firstWhere((BoardInfo b) => b.items.any((HealthItem i) => i.id == id)).board;
