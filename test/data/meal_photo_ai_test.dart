import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/meal_photo_ai.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import '../support/sqlite_host.dart';
import '../support/meal_photo_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);
  test(
      'relectura SQLite conserva porciones, cifras y origen estimado sin crear catálogo',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final repo = NutritionRepository(db);
    final before = await db.select(db.foods).get();
    final estimate = MealPhotoAi.parse(jsonEncode(fictionalMeal()));
    final draft = MealDraft(
        date: DateTime(2026, 10, 6),
        slot: MealSlot.almuerzo,
        notes: 'Estimación por foto',
        items: [estimate.items.first.toDraft(1.5)]);
    expect(await db.select(db.meals).get(), isEmpty);
    final id = await repo.saveMeal(draft);
    final restored = await repo.loadMeal(id);
    expect(restored.items.single.macros.kcal, 315);
    expect(restored.items.single.macros.protein, 6);
    expect(restored.items.single.quantity, 1.5);
    expect(restored.items.single.sourceVerified, isNull);
    expect(restored.notes, 'Estimación por foto');
    expect((await db.select(db.foods).get()).length, before.length);
  });
  test('foto reencodificada sin datos anexos y resolución limitada', () async {
    final photo = Uint8List.fromList(
        [...fictionalPhoto(), ...utf8.encode('GPS ubicación ficticia')]);
    final encoded = await prepareMealPhoto(photo);
    expect(utf8.decode(encoded, allowMalformed: true), isNot(contains('GPS')));
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    expect(descriptor.width, 1);
    expect(descriptor.height, 1);
    descriptor.dispose();
    buffer.dispose();
    await expectLater(prepareMealPhoto(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<AiError>()));
  });
  test('solamente imagen y activación al endpoint fijo; todo queda estimado',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.toString(),
          'https://www.control360i.co/app/seguimiento/comida');
      expect(jsonDecode(request.body), {
        'hwid': 'SEG-FICTICIO',
        'license_key': 'AAAA-BBBB-CCCC-DDDD',
        'mime': 'image/png',
        'photo_base64': base64Encode(fictionalPhoto()),
      });
      return http.Response(jsonEncode(fictionalMeal()), 200);
    });
    final estimate = await MealPhotoAi(client)
        .analyze(fictionalPhoto(), 'SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
    final draft = estimate.items.first.toDraft(1.5);
    expect(draft.macros.kcal, 315);
    expect(draft.macros.protein, 6);
    expect(draft.foodId, isNull);
    expect(draft.sourceVerified, isNull);
    expect(draft.quantityUnit, 'porción');
    expect(calls, 1);
    await expectLater(
        MealPhotoAi(client)
            .analyze(Uint8List(MealPhotoAi.maxPhotoBytes + 1), '', ''),
        throwsA(isA<AiError>()));
    expect(calls, 1);
  });
  test(
      'salida imposible, vacía o de otro modelo falla antes de formar borrador',
      () {
    Map<String, dynamic> meal(Map<String, dynamic> d) =>
        d['meal'] as Map<String, dynamic>;
    Map<String, dynamic> firstItem(Map<String, dynamic> d) =>
        (meal(d)['items'] as List<dynamic>).first as Map<String, dynamic>;
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (d) => d['model'] = 'otro',
      (d) => meal(d)['items'] = [],
      (d) => meal(d)['uncertainties'] = ['x' * 301],
      (d) => firstItem(d)['kcal'] = -1,
      (d) => firstItem(d)['kcal'] = '210',
      (d) => firstItem(d)['protein'] = 199,
      (d) => firstItem(d)['label'] = '',
    ]) {
      final data =
          jsonDecode(jsonEncode(fictionalMeal())) as Map<String, dynamic>;
      mutation(data);
      // Items vacíos con explicación son una abstención válida.
      if ((data['meal'] as Map)['items'] is List &&
          ((data['meal'] as Map)['items'] as List).isEmpty) {
        expect(MealPhotoAi.parse(jsonEncode(data)).items, isEmpty);
      } else {
        expect(
            () => MealPhotoAi.parse(jsonEncode(data)), throwsFormatException);
      }
    }
    expect(
        () => MealPhotoAi.parse(jsonEncode({
              'model': 'gpt-6-luna',
              'meal': {'items': [], 'uncertainties': []}
            })),
        throwsFormatException);
  });
  test('fallo de proveedor no filtra cuerpo ni reintenta; timeout acotado',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('secret server detail', 503);
    });
    await expectLater(
        MealPhotoAi(client).analyze(fictionalPhoto(), '', ''),
        throwsA(isA<AiError>().having(
            (e) => e.message, 'sanitizado', isNot(contains('secret')))));
    expect(calls, 1);
    await expectLater(
        MealPhotoAi(MockClient((_) => Completer<http.Response>().future),
                timeout: const Duration(milliseconds: 10))
            .analyze(fictionalPhoto(), '', ''),
        throwsA(isA<AiError>()));
  });
}
