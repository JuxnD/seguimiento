import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/update_service.dart';

/// §16.13: la descarga del APK la abre MainActivity.kt en su propia tarea y
/// cierra la de la app. Aquí se prueba el lado Dart del canal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('seguimiento/sistema');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final apk = Uri.parse('https://github.com/JuxnD/seguimiento/releases/download/v1.16.0/seguimiento-v1.16.0.apk');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('pide abrir la descarga con la URL del APK', () async {
    MethodCall? asked;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked = call;
      return true;
    });
    expect(await const UpdateLauncher().openApkDownload(apk), isTrue);
    expect(asked?.method, 'openApkDownload');
    expect(asked?.arguments, {'url': '$apk'});
  });

  test('si Android no pudo o no hay Android debajo, devuelve false para abrirla como antes', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await const UpdateLauncher().openApkDownload(apk), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'x'));
    expect(await const UpdateLauncher().openApkDownload(apk), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await const UpdateLauncher().openApkDownload(apk), isFalse, reason: 'MissingPluginException');
  });
}
