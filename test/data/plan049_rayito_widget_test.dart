import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/rayito_widget_bridge.dart';
import 'package:seguimiento/domain/mascot.dart';

/// Plan 049, slice 4: el widget de inicio recibe sólo lo que Hoy calculó,
/// más el dibujo real de Rayito en PNG. Sin el lado nativo no rompe nada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('seguimiento/widget');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 1;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  const data = RayitoWidgetData(
      phase: MascotPhase.cargado,
      mood: MascotMood.contento,
      streak: 5,
      today: 'Tren superior');

  test('envía título, racha, qué toca hoy y un PNG real', () async {
    await RayitoWidgetBridge(android: true).update(data);
    expect(calls, hasLength(1));
    final args = (calls.single.arguments as Map).cast<String, Object?>();
    expect(calls.single.method, 'update');
    expect((args['title'], args['streak'], args['today']),
        ('Rayito', 'Nivel 3 · 5 días de racha', 'Hoy: Tren superior'));
    final png = args['png']! as Uint8List;
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'firma PNG');
    expect(png.length, greaterThan(2000), reason: 'no es una imagen vacía');
    expect(args.keys.toSet(),
        {'title', 'streak', 'today', 'date', 'semanticLabel', 'png'},
        reason: 'nada más sale hacia el widget');
    expect(args['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('sin racha y 1 día se dicen bien', () {
    expect(
        const RayitoWidgetData(
                phase: MascotPhase.dormido,
                mood: MascotMood.dormido,
                streak: 0,
                today: 'Descanso')
            .streakLine,
        'Sin racha todavía');
    expect(
        const RayitoWidgetData(
                phase: MascotPhase.despierto,
                mood: MascotMood.contento,
                streak: 1,
                today: 'Piernas')
            .streakLine,
        'Nivel 2 · 1 día de racha');
  });

  test('fuera de Android no llama al canal', () async {
    await RayitoWidgetBridge(android: false).update(data);
    expect(calls, isEmpty);
  });

  test('sin el lado nativo no lanza', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await RayitoWidgetBridge(android: true).update(data);
  });

  test('serializa dos lecturas: el dato nuevo llega después del antiguo',
      () async {
    final firstArrived = Completer<void>();
    final firstAck = Completer<int>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (calls.length == 1) {
        firstArrived.complete();
        return firstAck.future;
      }
      return 1;
    });
    final bridge = RayitoWidgetBridge(android: true);
    final first = bridge.update(data);
    await firstArrived.future;
    final newest = bridge.update(const RayitoWidgetData(
        phase: MascotPhase.cargado,
        mood: MascotMood.contento,
        streak: 6,
        today: 'Piernas'));
    expect(calls, hasLength(1), reason: 'no se adelanta mientras falta ACK');
    firstAck.complete(1);
    expect(await first, isTrue);
    expect(await newest, isTrue);
    expect((calls.last.arguments as Map)['streak'], 'Nivel 3 · 6 días de racha');
  });

  test('un error del canal no confirma envío y permite reintento', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (++attempts == 1) {
        throw PlatformException(code: 'synthetic_write_failure');
      }
      return 1;
    });
    final bridge = RayitoWidgetBridge(android: true);
    expect(await bridge.update(data), isFalse);
    expect(await bridge.update(data), isTrue);
    expect(attempts, 2);
  });

  test('clear cancela una lectura encolada y deja la frontera vacía', () async {
    final bridge = RayitoWidgetBridge(android: true);
    final old = bridge.update(data);
    final cleared = bridge.clear();
    expect(await old, isFalse);
    expect(await cleared, isTrue);
    expect(calls.map((call) => call.method), ['clear']);
  });

  test(
      'clear va tras el envío en vuelo y rechaza escrituras del perfil retirado',
      () async {
    final arrived = Completer<void>();
    final ack = Completer<int>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (calls.length == 1) {
        arrived.complete();
        return ack.future;
      }
      return 1;
    });
    final bridge = RayitoWidgetBridge(android: true);
    final old = bridge.update(data);
    await arrived.future;
    final clearing = bridge.clear();
    expect(await bridge.update(data), isFalse);
    expect(calls.map((call) => call.method), ['update']);
    ack.complete(1);
    expect(await old, isTrue);
    expect(await clearing, isTrue);
    expect(calls.map((call) => call.method), ['update', 'clear']);
    bridge.enable();
    expect(await bridge.update(data), isTrue);
    expect(calls.map((call) => call.method), ['update', 'clear', 'update']);
  });
}
