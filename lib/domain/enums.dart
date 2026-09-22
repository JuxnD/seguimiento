/// Enumeraciones del dominio. Se persisten por nombre (`textEnum`), así que
/// renombrar un valor exige migración. Añadir valores al final es seguro.
library;

enum DayType { circuito, bloques, futbol, descanso }

extension DayTypeLabel on DayType {
  String get label => switch (this) {
        DayType.circuito => 'Circuito',
        DayType.bloques => 'Bloques',
        DayType.futbol => 'Fútbol',
        DayType.descanso => 'Descanso',
      };

  /// Días que cuentan como sesión de entrenamiento esperada.
  bool get isTraining => this == DayType.circuito || this == DayType.bloques;
}

/// Tipo de una sesión registrada. El fútbol va aparte (FootballGames).
enum SessionType { circuito, bloques, otro }

extension SessionTypeLabel on SessionType {
  String get label => switch (this) {
        SessionType.circuito => 'Circuito',
        SessionType.bloques => 'Bloques',
        SessionType.otro => 'Otro',
      };
}

enum MealSlot { desayuno, almuerzo, merienda, cena, otro }

extension MealSlotLabel on MealSlot {
  String get label => switch (this) {
        MealSlot.desayuno => 'Desayuno',
        MealSlot.almuerzo => 'Almuerzo',
        MealSlot.merienda => 'Merienda',
        MealSlot.cena => 'Cena',
        MealSlot.otro => 'Otro',
      };
}

/// Base de los macros de un alimento del catálogo.
/// `unit`: macros por 1 unidad (huevo, lata). `per100`: por 100 g o 100 ml.
enum FoodBasis { unit, per100 }

enum MeasureSite {
  abdomen,
  cinturaEstrecha,
  cadera,
  brazoRelajado,
  brazoTensionado,
  cuadriceps,
  pantorrilla,
  pecho,
  hombros,
}

extension MeasureSiteLabel on MeasureSite {
  String get label => switch (this) {
        MeasureSite.abdomen => 'Abdomen (ombligo)',
        MeasureSite.cinturaEstrecha => 'Cintura estrecha',
        MeasureSite.cadera => 'Cadera',
        MeasureSite.brazoRelajado => 'Brazo relajado',
        MeasureSite.brazoTensionado => 'Brazo tensionado',
        MeasureSite.cuadriceps => 'Cuádriceps',
        MeasureSite.pantorrilla => 'Pantorrilla',
        MeasureSite.pecho => 'Pecho',
        MeasureSite.hombros => 'Hombros',
      };
}

enum LengthUnit { cm, inch }

extension LengthUnitLabel on LengthUnit {
  String get label => this == LengthUnit.cm ? 'cm' : 'in';
}
