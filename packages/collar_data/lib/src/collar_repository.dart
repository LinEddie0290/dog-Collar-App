import 'dart:async';

import 'collar_data_source.dart';
import 'conn_status.dart';
import 'filters.dart';
import 'raw_archive.dart';
import 'raw_frame.dart';
import 'sensor_sample.dart';

/// Ties the data layer together and is the ONLY thing the UI layer needs:
///
///   frames --> [archive raw to disk] --> parse --> [filter] --> cleanStream
///
/// The UI subscribes to [cleanStream] + [status] and reads [recent]; it never
/// sees sockets, JSON, or files.
///
/// Order matters and matches the spec: the raw frame is persisted FIRST, before
/// parsing or filtering, so nothing is ever lost to a filter bug.
class CollarRepository {
  final CollarDataSource source;
  final RawArchive archive;
  final SampleFilter filter;

  /// How many recent samples to keep in memory for chart warm-up.
  final int bufferSize;

  final _clean = StreamController<SensorSample>.broadcast();
  final _recent = <SensorSample>[];
  StreamSubscription<RawFrame>? _sub;

  // Frames are processed one at a time via this chain. Stream.listen does not
  // await async callbacks, so without serialising, concurrent _process calls
  // would race on the archive's file sink and the buffer.
  Future<void> _tail = Future<void>.value();

  CollarRepository({
    required this.source,
    required this.archive,
    SampleFilter? filter,
    this.bufferSize = 600,
  }) : filter = filter ?? SampleFilter();

  /// Filtered, display-ready samples.
  Stream<SensorSample> get cleanStream => _clean.stream;

  /// Connection state, passed straight through from the source.
  Stream<ConnStatus> get status => source.status;

  /// Most recent samples (oldest first), for initialising charts.
  List<SensorSample> get recent => List.unmodifiable(_recent);

  /// Start listening and connect the source.
  Future<void> start() async {
    // Sync callback that enqueues async work, keeping processing serialized.
    _sub = source.frames.listen((f) {
      _tail = _tail.then((_) => _process(f));
    });
    await source.connect();
  }

  Future<void> _process(RawFrame f) async {
    if (_clean.isClosed) return; // stopped while this was queued
    await archive.write(f); // 1) persist raw, faithfully, first
    if (_clean.isClosed) return;
    final parsed = SensorSample.fromRaw(f); // 2) parse
    final clean = filter.apply(parsed); // 3) denoise
    _recent.add(clean); // 4) buffer for the UI
    if (_recent.length > bufferSize) _recent.removeAt(0);
    _clean.add(clean); // 5) expose to the UI
  }

  Future<void> stop() async {
    await _sub?.cancel();
    await _tail; // drain any in-flight frame before tearing down
    await source.disconnect();
    await archive.close();
    if (!_clean.isClosed) await _clean.close();
  }
}
