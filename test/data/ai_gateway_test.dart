import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/ai_gateway.dart';

void main() {
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
