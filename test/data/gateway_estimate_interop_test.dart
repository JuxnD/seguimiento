import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/meal_assistant.dart';
import '../support/meal_estimate_fixture.dart';

void main() {
  final gateway = Platform.environment['SEGUIMIENTO_ESTIMATE_GATEWAY'];
  final php = Platform.environment['SEGUIMIENTO_ESTIMATE_PHP'];
  test('Dart actual→PHP actual→Dart validado (transporte proveedor ficticio)',
      () async {
    const text = '250 g de arroz chino';
    final result = estimateResult([estimateItem('Arroz chino')], [(text, 0)]);
    final assistant = MealAssistant(MockClient((request) async {
      final process = await Process.start(php!, [
        '-d',
        'display_errors=0',
        '$gateway/scripts/seguimiento_estimate_test.php',
        '--fixture'
      ]);
      process.stdin.write(
          jsonEncode({'body': jsonDecode(request.body), 'result': result}));
      await process.stdin.close();
      final out = process.stdout.transform(utf8.decoder).join();
      final err = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode;
      expect(code, 0, reason: await err);
      return http.Response(await out, 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final estimate = await assistant.estimateMeal(
        text: text,
        catalog: [],
        hwid: 'SEG-FICTICIO',
        license: 'AAAA-BBBB-CCCC-DDDD');
    expect(estimate.items.single.quantity, 250);
    expect(estimate.items.single.macros!.kcal, 500);
    expect(estimate.coverage.single.text, text);
  },
      skip: gateway == null || php == null
          ? 'Requiere SEGUIMIENTO_ESTIMATE_GATEWAY y SEGUIMIENTO_ESTIMATE_PHP; no es prueba remota.'
          : false);
}
