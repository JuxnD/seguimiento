import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'gate compara capturas y rechaza mutantes; fixtures no autorizan publicación',
      () async {
    final result = await Process.run('python', ['tool/pilot_gate_test.py']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr.toString(), contains('Ran 17 tests'));
    expect(result.stderr.toString(), contains('OK'));
  });
}
