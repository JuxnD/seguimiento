import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// `flutter test` corre en el escritorio, donde no está la librería que
/// `sqlite3_flutter_libs` empaqueta para Android/iOS. En Windows se usa la
/// que trae el sistema; en macOS/Linux, la del sistema operativo.
void useHostSqlite() {
  if (Platform.isWindows) {
    open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open('winsqlite3.dll'));
  }
}
