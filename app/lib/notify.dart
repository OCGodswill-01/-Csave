// Phone builds use the real reminders; browser builds use a no-op stub.
export 'notify_stub.dart' if (dart.library.io) 'notify_io.dart';
