/// Vital signs from the collar's accelerometer — pure Dart, zero dependencies.
///
/// The app feeds in accelerometer magnitude and gets back a heart rate, a
/// respiration rate, beat-to-beat intervals, and an explicit quality verdict.
/// No FFT and no external packages, so the whole thing runs inside a 60-second
/// measurement on a phone and can be unit-tested with a bare `dart` SDK.
///
/// ⚠️ This is ballistocardiography, not electrocardiography. It measures the
/// body's mechanical recoil from each heartbeat. It yields a rate and its
/// variability; it cannot diagnose a rhythm. Anything shown to a veterinarian
/// must carry the [VitalsQuality] verdict alongside the number.
library;

export 'src/biquad.dart';
export 'src/vitals_analyzer.dart';
