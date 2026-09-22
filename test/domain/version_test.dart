import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/version.dart';

void main() {
  group('comparación de versiones', () {
    test('ordena por major, minor y patch', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });

    test('tolera el prefijo v, el build y las versiones cortas', () {
      expect(isNewerVersion('v1.2.0', '1.1.9'), isTrue);
      expect(isNewerVersion('1.2.0+15', '1.2.0'), isFalse);
      expect(isNewerVersion('1.3', '1.2.9'), isTrue);
      expect(AppVersion.tryParse('v2.1.3+9').toString(), '2.1.3');
    });

    test('ante texto raro no anuncia actualización', () {
      expect(isNewerVersion('ultima', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', ''), isFalse);
      expect(isNewerVersion('1.0.0.0', '1.0.0'), isFalse);
      expect(AppVersion.tryParse('-1.0'), isNull);
    });
  });
}
