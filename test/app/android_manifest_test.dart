import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lo que ninguna prueba de pantalla ve: cómo Android acomoda la app en
/// recientes y qué otras apps deja nombrar.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final activity = RegExp(r'<activity\s[^>]*android:name="\.MainActivity"[^>]*>').firstMatch(manifest)!.group(0)!;

  test('una sola tarea: singleTask y sin afinidad vacía (§16.13)', () {
    expect(activity, contains('android:launchMode="singleTask"'));
    expect(activity, isNot(contains('android:taskAffinity')),
        reason: 'con taskAffinity="" el "Abrir" del instalador creaba una segunda tarea');
  });

  test('puede leer el nombre de la app del reloj (§16.14)', () {
    expect(manifest, contains('<package android:name="com.moyoung.innov"/>'));
  });
}
