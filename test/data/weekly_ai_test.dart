import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/weekly_ai.dart';

void main() {
  const report = 'Semana ficticia\nProteína: 130 g\nPeso: sin registro';
  Map<String, Object> note() => {
        'kind': 'missing',
        'text': 'Falta el registro de peso para comparar.',
        'quote': 'Peso: sin registro'
      };
  String response(Map<String, Object> n) => jsonEncode({
        'model': 'gpt-6-luna',
        'notes': [n]
      });
  test('solo envía informe elegido al endpoint fijo, sin clave de OpenAI',
      () async {
    final client = MockClient((request) async {
      expect(request.url, WeeklyAi.endpoint);
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {
        'hwid': 'SEG-ficticio',
        'license_key': 'AAAA-BBBB-CCCC-DDDD',
        'report': report
      });
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response(response(note()), 200);
    });
    final result = await WeeklyAi(client)
        .analyze(report, 'SEG-ficticio', 'AAAA-BBBB-CCCC-DDDD');
    expect(result.single.quote, 'Peso: sin registro');
  });
  test('rechaza cita inventada, cifras en explicación y tipo no permitido', () {
    for (final change in [
      {'quote': 'Peso: 99 kg'},
      {'text': 'Comiste 999 gramos.'},
      {'kind': 'prescription'}
    ]) {
      expect(() => WeeklyAi.parse(response(note()..addAll(change)), report),
          throwsFormatException);
    }
    expect(() => WeeklyAi.parse('{"model":"gpt-6-luna","notes":[]}', report),
        throwsFormatException);
  });
  test('mide texto y cita en puntos Unicode, incluidos emojis', () {
    final unicodeReport = '😀' * 501;
    final valid = note()
      ..['text'] = '😀' * 350
      ..['quote'] = '😀' * 500;
    expect(WeeklyAi.parse(response(valid), unicodeReport), hasLength(1));
    final tooLongText = note()..['text'] = '😀' * 351;
    expect(() => WeeklyAi.parse(response(tooLongText), unicodeReport),
        throwsFormatException);
    final tooLongQuote = note()..['quote'] = '😀' * 501;
    expect(() => WeeklyAi.parse(response(tooLongQuote), unicodeReport),
        throwsFormatException);
  });
  test('errores no filtran respuesta remota ni licencia', () async {
    for (final code in [401, 403, 429, 503, 500]) {
      final client = MockClient((_) async =>
          http.Response('sk-ficticio:provider-private-data', code));
      try {
        await WeeklyAi(client).analyze(report, 'SEG-x', 'ficticia');
        fail('should fail');
      } on AiError catch (e) {
        expect(e.message, isNot(contains('sk-ficticio')));
      }
    }
  });
  test('timeout y fallo al leer respuesta se consideran error', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    await expectLater(
        WeeklyAi(client, timeout: const Duration(milliseconds: 5))
            .analyze(report, 'x', 'y'),
        throwsA(isA<AiError>()));
    final broken =
        MockClient((_) async => http.Response('<html>broken</html>', 200));
    await expectLater(
        WeeklyAi(broken).analyze(report, 'x', 'y'), throwsA(isA<AiError>()));
  });
  test('vacío o muy largo nunca llama al servidor', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('', 500);
    });
    for (final bad in ['', List.filled(48001, 'a').join()]) {
      await expectLater(
          WeeklyAi(client).analyze(bad, 'x', 'y'), throwsA(isA<AiError>()));
    }
    expect(calls, 0);
  });
}
