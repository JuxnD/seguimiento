import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/ai_gateway.dart';

void main() {
  test('envía JSON grande como un único campo multipart sin perder bytes',
      () async {
    for (final size in [16383, 16384, 1400000]) {
      final overhead = utf8.encode(jsonEncode({'value': ''})).length;
      final input = <String, Object?>{'value': 'A' * (size - overhead)};
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (size < 16384) {
          expect(
              request.headers['content-type'], startsWith('application/json'));
          expect(jsonDecode(utf8.decode(request.bodyBytes)), input);
        } else {
          final type = request.headers['content-type']!;
          expect(type, startsWith('multipart/form-data; boundary='));
          final boundary = type.split('boundary=').last;
          final wire = utf8.decode(request.bodyBytes);
          expect(wire, contains('name="payload"'));
          expect(wire, isNot(contains('filename=')));
          final start = wire.indexOf('\r\n\r\n') + 4;
          final end = wire.lastIndexOf('\r\n--$boundary--');
          expect(jsonDecode(wire.substring(start, end)), input);
        }
        return http.Response('{"ok":true}', 200);
      });
      await postAiJson(
          client,
          Uri.parse('https://www.control360i.co/app/seguimiento/asistir'),
          input);
      expect(calls, 1);
      client.close();
    }
  });

  test('decide multipart por bytes UTF-8 y conserva el texto Unicode',
      () async {
    final input = <String, Object?>{'text': 'ñ🧡' * 3000};
    final client = MockClient((request) async {
      expect(
          request.headers['content-type'], startsWith('multipart/form-data'));
      final wire = utf8.decode(request.bodyBytes);
      expect(wire, contains(jsonEncode(input)));
      return http.Response('{}', 200);
    });
    await postAiJson(
        client,
        Uri.parse('https://www.control360i.co/app/seguimiento/analizar'),
        input);
    client.close();
  });

  Map<String, Object?> envelope({
    String status = 'success',
    String task = 'report_question',
    Object? quota = const {
      'remaining': 3,
      'limit': 4,
      'reset_at': '2026-10-07T00:00:00Z',
    },
    Object? result = const {
      'answer': 'El registro muestra una variación.',
      'citations': []
    },
  }) =>
      {
        'status': status,
        'contract': 2,
        'task': task,
        'model': 'gpt-6-luna',
        'result': result,
        'quota': quota,
      };

  test('usa solo el endpoint v2 fijo y valida el envelope', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(),
          'https://www.control360i.co/app/seguimiento/asistir');
      expect(jsonDecode(request.body), {
        'contract': 2,
        'task': 'report_question',
        'input': {'question': '¿Qué cambió?', 'sources': []},
        'hwid': 'SEG-FICTICIO',
        'license_key': 'AAAA-BBBB-CCCC-DDDD',
      });
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response(jsonEncode(envelope()), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final gateway = AiGatewayClient(client);
    final result = await gateway.assist(
        task: 'report_question',
        input: const {'question': '¿Qué cambió?', 'sources': []},
        hwid: 'SEG-FICTICIO',
        license: 'AAAA-BBBB-CCCC-DDDD');
    expect(result['answer'], 'El registro muestra una variación.');
    expect(gateway.lastQuota?.remaining, 3);
    expect(gateway.lastQuota?.resetAt?.isUtc, isTrue);
  });

  test('rechaza status, contract, task, model y result inesperados', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (v) => v['status'] = 'error',
      (v) => v['contract'] = 1,
      (v) => v['task'] = 'exercise_question',
      (v) => v['model'] = 'other',
      (v) => v['result'] = [],
    ];
    for (final mutate in mutations) {
      final data = envelope();
      mutate(data);
      expect(
          () => AiGatewayClient(MockClient(
              (_) async => http.Response(jsonEncode(data), 200, headers: {
                    'content-type': 'application/json; charset=utf-8'
                  }))).assist(
              task: 'report_question',
              input: const {},
              hwid: 'SEG-X',
              license: 'AAAA-BBBB-CCCC-DDDD'),
          throwsA(isA<AiError>()));
    }
  });

  test('429 conserva solo una cuota válida y no filtra detalle remoto',
      () async {
    final gateway = AiGatewayClient(MockClient((_) async => http.Response(
        jsonEncode({
          'status': 'error',
          'error': {'code': 'quota_exceeded', 'detail': 'private-body'},
          'quota': {
            'remaining': 0,
            'limit': 4,
            'reset_at': '2026-10-07T00:00:00Z',
          }
        }),
        429,
        headers: {'content-type': 'application/json; charset=utf-8'})));
    await expectLater(
        gateway.assist(
            task: 'report_question',
            input: const {},
            hwid: 'SEG-X',
            license: 'AAAA-BBBB-CCCC-DDDD'),
        throwsA(isA<AiError>()
            .having((e) => e.code, 'código estable', 'quota_exceeded')
            .having((e) => e.quota?.remaining, 'restantes', 0)
            .having((e) => e.message, 'mensaje saneado',
                isNot(contains('private-body')))));
    expect(gateway.lastQuota?.remaining, 0);
  });

  test('status consulta sin datos y expone activación y cuota válidas',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/app/seguimiento/asistir');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['task'], 'status');
      expect(body['input'], isEmpty);
      expect(body.keys, containsAll(['hwid', 'license_key']));
      return http.Response(
          jsonEncode(envelope(task: 'status', result: {'enabled': true})), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final status = await AiGatewayClient(client)
        .status(hwid: 'SEG-FICTICIO', license: 'AAAA-BBBB-CCCC-DDDD');
    expect(status.enabled, isTrue);
    expect(status.quota?.remaining, 3);
    expect(status.message, contains('habilitada'));
  });

  test('status 503 falla cerrado y conserva la cuota remota permitida',
      () async {
    final status = await AiGatewayClient(MockClient((_) async => http.Response(
            jsonEncode({
              'error': {'code': 'service_not_configured'},
              'quota': {
                'remaining': 0,
                'limit': 4,
                'reset_at': '2026-10-07T00:00:00Z',
              }
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'})))
        .status(hwid: 'SEG-FICTICIO', license: 'AAAA-BBBB-CCCC-DDDD');
    expect(status.enabled, isFalse);
    expect(status.quota?.remaining, 0);
    expect(status.message, contains('aún no está habilitado'));
  });

  test('cuota malformada no reemplaza una lectura válida', () async {
    var response = jsonEncode(envelope());
    final gateway = AiGatewayClient(MockClient((_) async => http.Response(
        response, 200,
        headers: {'content-type': 'application/json; charset=utf-8'})));
    await gateway.assist(
        task: 'report_question', input: const {}, hwid: 'SEG-X', license: 'x');
    expect(gateway.lastQuota?.remaining, 3);
    response = jsonEncode(envelope(quota: {'remaining': -1, 'limit': 4}));
    await gateway.assist(
        task: 'report_question', input: const {}, hwid: 'SEG-X', license: 'x');
    expect(gateway.lastQuota?.remaining, 3);
  });

  test('respuesta sobredimensionada y timeout fallan de forma acotada',
      () async {
    final large = AiGatewayClient(MockClient((_) async => http.Response(
        'x' * (32 * 1024 + 1), 200,
        headers: {'content-type': 'application/json; charset=utf-8'})));
    await expectLater(
        large.assist(
            task: 'status', input: const {}, hwid: 'SEG-X', license: 'x'),
        throwsA(isA<AiError>()));
    final stuck = AiGatewayClient(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 5));
    await expectLater(
        stuck.assist(
            task: 'status', input: const {}, hwid: 'SEG-X', license: 'x'),
        throwsA(isA<AiError>()));
  });
}
