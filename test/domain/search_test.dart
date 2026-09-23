import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/search.dart';

void main() {
  test('sin tildes ni mayúsculas', () {
    expect(matchesQuery('Plátano', 'platano'), isTrue);
    expect(matchesQuery('Atún en agua', 'ATUN'), isTrue);
    expect(matchesQuery('Piña', 'pina'), isTrue);
  });

  test('palabras en cualquier orden', () {
    expect(matchesQuery('Pechuga de pollo', 'pollo pechuga'), isTrue);
    expect(matchesQuery('Pechuga de pollo', 'pollo res'), isFalse);
  });

  test('consulta vacía o con espacios coincide con todo', () {
    expect(matchesQuery('Huevo', ''), isTrue);
    expect(matchesQuery('Huevo', '   '), isTrue);
  });
}
