/// One frame exactly as it arrived from the collar, plus the phone's receive
/// time. This is what gets archived to disk *before* any parsing or filtering.
///
/// [rxTs] is the phone clock (epoch ms) at the moment the frame was received.
/// Like on the server, this is the only trustworthy time base — the collar's
/// own clock (inside [raw] as `ts`) can drift, so we stamp our own.
///
/// [raw] is the decoded JSON of the frame, stored untouched. We never mutate
/// its contents — faithful in, faithful to disk.
class RawFrame {
  final int rxTs;
  final Map<String, dynamic> raw;

  const RawFrame(this.rxTs, this.raw);
}
