/// Pet-collar data layer — pure Dart, zero UI / zero Flutter imports.
///
/// The UI layer imports only this file and works against [CollarRepository]:
/// subscribe to `cleanStream` + `status`, read `recent`. It never sees sockets,
/// JSON, or files.
library collar_data;

export 'src/conn_status.dart';
export 'src/raw_frame.dart';
export 'src/sensor_sample.dart';
export 'src/collar_data_source.dart';
export 'src/fake_collar_data_source.dart';
export 'src/websocket_collar_data_source.dart';
export 'src/raw_archive.dart';
export 'src/filters.dart';
export 'src/collar_repository.dart';
