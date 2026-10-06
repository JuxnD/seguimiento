import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:seguimiento/data/meal_assistant.dart';
import 'package:seguimiento/data/meal_photo_ai.dart';

import '../test/support/qa_label_photo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const license = String.fromEnvironment('SEGUIMIENTO_QA_LICENSE');
  const hwid = String.fromEnvironment('SEGUIMIENTO_QA_HWID');
  testWidgets(
      'Android: foto sintética preparada llega al gateway y lee etiqueta',
      (tester) async {
    final photo = await prepareMealPhoto(base64Decode(qaLabelPngBase64));
    expect(photo.length, greaterThan(12 * 1024));
    final client = http.Client();
    try {
      final assistant = MealAssistant(client);
      final label = await assistant.readFoodLabel(
          photo: photo, hwid: hwid, license: license);
      expect(label.basis, 'portion');
      expect(label.unit, 'g');
      expect(label.servingQuantity, 30);
      expect(label.kcal, 150);
      expect(label.protein, 3);
      expect(label.carbs, 24);
      expect(label.fat, 4);
      expect(assistant.lastQuota?.limit, 20);
    } finally {
      client.close();
    }
  }, skip: license.isEmpty || hwid.isEmpty);
}
