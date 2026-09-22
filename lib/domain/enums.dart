/// Enumeraciones del dominio. Se persisten por nombre (`textEnum`), así que
/// renombrar un valor exige migración. Añadir valores al final es seguro.
library;

enum DayType { circuito, bloques, futbol, descanso, circuitoLigero, progresion }

extension DayTypeLabel on DayType {
  String get label => switch (this) {
        DayType.circuito => 'Circuito',
        DayType.circuitoLigero => 'Circuito ligero',
        DayType.progresion => 'Progresión',
        DayType.bloques => 'Bloques',
        DayType.futbol => 'Fútbol',
        DayType.descanso => 'Descanso',
      };

  /// Días que cuentan como sesión de entrenamiento esperada.
  bool get isTraining => this != DayType.futbol && this != DayType.descanso;

  /// Días que se registran contando rondas.
  bool get isCircuit =>
      this == DayType.circuito || this == DayType.circuitoLigero || this == DayType.progresion;
}

/// Tipo de una sesión registrada. El fútbol va aparte (FootballGames).
enum SessionType { circuito, bloques, otro, circuitoLigero, progresion }

extension SessionTypeLabel on SessionType {
  String get label => switch (this) {
        SessionType.circuito => 'Circuito',
        SessionType.circuitoLigero => 'Circuito ligero',
        SessionType.progresion => 'Progresión',
        SessionType.bloques => 'Bloques',
        SessionType.otro => 'Otro',
      };

  /// Las sesiones de circuito son las que cuentan rondas y récords.
  bool get isCircuit =>
      this == SessionType.circuito ||
      this == SessionType.circuitoLigero ||
      this == SessionType.progresion;

  DayType get asDayType => switch (this) {
        SessionType.circuito => DayType.circuito,
        SessionType.circuitoLigero => DayType.circuitoLigero,
        SessionType.progresion => DayType.progresion,
        SessionType.bloques => DayType.bloques,
        SessionType.otro => DayType.bloques,
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

/// De dónde salen los macros de un alimento: leídos de la etiqueta del
/// empaque o tomados de una tabla de referencia (promedio, no medición).
enum MacroSource { etiqueta, referencia }

extension MacroSourceLabel on MacroSource {
  String get label => this == MacroSource.etiqueta ? 'etiqueta' : 'referencia';

  bool get isVerified => this == MacroSource.etiqueta;
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
