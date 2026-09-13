/// One frame exactly as it arrived from the collar, plus the phone's receive
/// time. This is what gets archived to disk *before* any parsing or filtering.
///
/// [rxTs] is the phone clock (epoch ms) at the moment the frame was received.
/// This is the only trustworthy time base — the collar's own clock is MCU
/// monotonic microseconds since boot, which resets on every reboot, so we
/// stamp our own.
///
/// [raw] is the frame's decoded content as a map, stored untouched. On the mock
/// path that is the JSON the mock server sent. On the real BLE path there is no
/// JSON on the wire, so this holds the decoded reading in the same key shape,
/// which keeps `SensorSample.fromRaw` and the archive format identical across
/// both transports.
///
/// [bytes] is the original binary logical frame, present only on the BLE path.
/// Archiving these is what makes the real link's archive genuinely faithful:
/// the decoded map is our interpretation, the bytes are the evidence. If a
/// decoder bug is ever suspected, these can be replayed through
/// `decodeFrame` — or through the firmware's own `pet_codec.py` — without the
/// dog having to walk past again.
class RawFrame {
  final int rxTs;
  final Map<String, dynamic> raw;

  /// The untouched PET v1 logical frame, when the source had one.
  final List<int>? bytes;

  const RawFrame(this.rxTs, this.raw, {this.bytes});
}
