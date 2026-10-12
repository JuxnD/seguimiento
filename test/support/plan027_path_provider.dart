import 'dart:io';

// path_provider_platform_interface llega como dependencia transitiva; no se
// añade al pubspec solo para sustituir el directorio en las pruebas.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// path_provider con un directorio temporal propio: las pruebas de fotos
/// cruzan archivos reales sin tocar datos del equipo.
class FakePathProvider extends PathProviderPlatform {
  FakePathProvider(this.documents);

  final Directory documents;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents.path;

  /// Instala el sustituto y devuelve el directorio de documentos.
  static Directory install() {
    final dir = Directory.systemTemp.createTempSync('seguimiento_027_docs');
    PathProviderPlatform.instance = FakePathProvider(dir);
    return dir;
  }
}
