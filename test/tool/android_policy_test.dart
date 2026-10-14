import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Android source policy rejects XML consumer mutations; native QA pending',
      () async {
    final result = await Process.run('python', ['tool/android_policy_test.py']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr.toString(), contains('Ran 16 tests'));
    expect(result.stderr.toString(), contains('OK'));
  });
}
