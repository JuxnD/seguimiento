import 'package:drift/drift.dart';

import '../domain/enums.dart';
import '../domain/reminders.dart';

// Convenciones (ver docs/modelo-datos.md):
// - Fechas: texto `YYYY-MM-DD` (día local). Horas: texto `HH:mm`.
// - Duraciones en segundos. Longitudes en cm. Peso en kg.
// - Enums por nombre (`textEnum`).

@DataClassName('ProfileRow')
class Profiles extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get birthDate => text().nullable()();
  RealColumn get heightCm => real().nullable()();
  TextColumn get startDate => text()();
  IntColumn get proteinMin => integer().withDefault(const Constant(130))();
  IntColumn get proteinMax => integer().withDefault(const Constant(160))();
  IntColumn get kcalTarget => integer().withDefault(const Constant(2400))();
  IntColumn get kcalFloor => integer().withDefault(const Constant(2000))();
  IntColumn get minWarmupSec => integer().withDefault(const Constant(360))();
  IntColumn get measureIntervalDays => integer().withDefault(const Constant(21))();

  /// Ventana recomendada de medición: [measureIntervalDays, measureIntervalMaxDays].
  IntColumn get measureIntervalMaxDays => integer().withDefault(const Constant(28))();

  /// Próxima medición acordada, si se fijó una fecha concreta.
  TextColumn get nextMeasurementDate => text().nullable()();
  IntColumn get cooldownTargetSec => integer().withDefault(const Constant(180))();

  /// Regla del plan: no se entrena al fallo. La app avisa si se marca uno.
  BoolColumn get neverToFailure => boolean().withDefault(const Constant(true))();
  TextColumn get lengthUnit => textEnum<LengthUnit>().withDefault(const Constant('cm'))();

  /// Meta de pasos diarios entre semana.
  IntColumn get stepsTarget => integer().withDefault(const Constant(7500))();

  /// Meta de kcal de los días de fútbol (sábado y domingo, §19.3). null =
  /// la misma de entre semana (`kcalTarget`).
  IntColumn get kcalTargetFootball => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Catálogo de ejercicios: evita que "Flexiones" y "flexiones" sean dos cosas.
@DataClassName('ExerciseRow')
class Exercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80).unique()();

  /// Referencia visual: se abre en el navegador.
  TextColumn get mediaUrl => text().nullable()();

  /// Claves de técnica, una por línea (3–5). Se muestran en el cronómetro.
  TextColumn get formCues => text().nullable()();

  /// Cómo se progresa este ejercicio ("pike → pies elevados → HSPU").
  TextColumn get progressionNote => text().nullable()();

  /// Progresa con carga externa (mochila, garrafas): el cronómetro pide kg.
  BoolColumn get tracksLoad => boolean().withDefault(const Constant(false))();

  /// Cómo se ancla la banda elástica: 'alto', 'medio', 'bajo' o 'manos'
  /// (§18.7). null = no usa banda.
  TextColumn get anchor => text().nullable()();
}

/// Versión inmutable del plan. Editar = crear versión nueva.
@DataClassName('PlanVersionRow')
class PlanVersions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get validFrom => text()();
  TextColumn get notes => text().nullable()();

  /// Esquema de periodización: 'v3' aplica descargas, Cindy/Tabata y
  /// burpees por semana (§18.6). null = plan plano, igual todas las semanas.
  TextColumn get scheme => text().nullable()();
}

@DataClassName('PlanDayRow')
class PlanDays extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planVersionId => integer().references(PlanVersions, #id, onDelete: KeyAction.cascade)();

  /// 1 = lunes … 7 = domingo.
  IntColumn get weekday => integer().check(weekday.isBetweenValues(1, 7))();
  TextColumn get type => textEnum<DayType>()();
  IntColumn get targetRounds => integer().nullable()();

  /// Descanso entre rondas del circuito (dentro de la ronda no se descansa).
  IntColumn get restBetweenRoundsSec => integer().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {planVersionId, weekday},
      ];
}

@DataClassName('PlanExerciseRow')
class PlanExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planDayId => integer().references(PlanDays, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  IntColumn get exerciseId => integer().references(Exercises, #id)();
  IntColumn get sets => integer().nullable()();
  IntColumn get repsMin => integer().nullable()();
  IntColumn get repsMax => integer().nullable()();
  IntColumn get restSec => integer().nullable()();

  /// Descanso máximo cuando el plan da un rango (90–120 s).
  IntColumn get restSecMax => integer().nullable()();
  TextColumn get grip => text().nullable()();

  /// null = trabajo principal del día; si no, el bloque extra ('core',
  /// 'cuádriceps', 'hombro') que va después de la sesión.
  TextColumn get block => text().nullable()();

  /// Bloques que alternan entre variantes: 'A' o 'B'.
  TextColumn get variant => text().nullable()();

  /// Ejercicios de sostén (plancha, hollow) en lugar de repeticiones.
  IntColumn get holdSecMin => integer().nullable()();
  IntColumn get holdSecMax => integer().nullable()();

  /// Las repeticiones o el sostén son por lado.
  BoolColumn get perSide => boolean().withDefault(const Constant(false))();
  IntColumn get rirMin => integer().nullable()();
  IntColumn get rirMax => integer().nullable()();

  /// Cómo progresa y qué hacer si algo se resiente.
  TextColumn get notes => text().nullable()();

  /// Superserie: los ejercicios del mismo grupo se alternan serie a serie y
  /// el descanso va después del último (§18.9).
  TextColumn get supersetGroup => text().nullable()();
}

@DataClassName('SessionRow')
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  TextColumn get startTime => text().nullable()();
  TextColumn get type => textEnum<SessionType>()();
  IntColumn get planDayId => integer().nullable().references(PlanDays, #id, onDelete: KeyAction.setNull)();
  IntColumn get totalSec => integer().withDefault(const Constant(0))();
  IntColumn get warmupSec => integer().withDefault(const Constant(0))();
  IntColumn get cooldownSec => integer().withDefault(const Constant(0))();

  /// Descansos entre series o rondas, sumados. Van aparte del trabajo neto.
  /// 0 en sesiones anteriores al esquema 7 o registradas a mano sin él.
  IntColumn get restSec => integer().withDefault(const Constant(0))();
  IntColumn get roundsDone => integer().nullable()();

  /// true si las rondas salieron de la estimación por tiempo.
  BoolColumn get roundsEstimated => boolean().withDefault(const Constant(false))();
  IntColumn get rpe => integer().nullable().check(rpe.isBetweenValues(1, 10))();
  IntColumn get limitingExerciseId => integer().nullable().references(Exercises, #id, onDelete: KeyAction.setNull)();
  TextColumn get context => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// El tipo no coincide con lo que el plan pedía ese día.
  BoolColumn get outOfPlan => boolean().withDefault(const Constant(false))();

  /// Se cerró antes de completar el plan (paré en la ronda 7 de 8).
  BoolColumn get incomplete => boolean().withDefault(const Constant(false))();

  /// Rondas o series que pedía el plan, copiadas al registrar.
  IntColumn get plannedRounds => integer().nullable()();

  // Condiciones de la regla de progresión. null = no se registró.
  BoolColumn get techniqueOk => boolean().nullable()();
  BoolColumn get fullRange => boolean().nullable()();
  BoolColumn get recoveryOk => boolean().nullable()();

  /// Guardada sola al terminar el cronómetro, sin pasar por el formulario
  /// (falta el RPE). Cuenta en Hoy y en el informe desde ya (§16.9).
  BoolColumn get pendingReview => boolean().withDefault(const Constant(false))();

  /// Formato de una sesión de resistencia (v3): 'cindy', 'tabata' o
  /// 'porTiempo'. null en el resto.
  TextColumn get mode => text().nullable()();

  /// AMRAP: repeticiones sueltas de la ronda que quedó a medias (Cindy
  /// "12 + 7"). null si no aplica.
  IntColumn get extraReps => integer().nullable()();

  /// Viene del historial anterior a la app (§16.16): cuenta para totales,
  /// rachas y días entrenados, no para récords ni medias.
  BoolColumn get imported => boolean().withDefault(const Constant(false))();

  /// Identidad de los peldaños realmente usados, JSON id → step:epoch.
  TextColumn get coreEpochs => text().nullable()();
}

/// Marcas del contador: segundos desde el inicio del circuito al cerrar cada ronda.
@DataClassName('SessionRoundRow')
class SessionRounds extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get roundIndex => integer()();
  IntColumn get elapsedSec => integer()();

  /// Trabajo de la ronda: de su arranque a la última repetición, sin el
  /// descanso que la precede. null en rondas anteriores al esquema 8 o del
  /// contador libre, que no separa el descanso.
  IntColumn get workSec => integer().nullable()();

  /// Descanso posterior a la ronda (0 en la última). null = no se midió.
  IntColumn get restSec => integer().nullable()();
}

@DataClassName('SessionSetRow')
class SessionSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer().references(Exercises, #id)();
  IntColumn get setIndex => integer()();
  IntColumn get reps => integer()();
  BoolColumn get split => boolean().withDefault(const Constant(false))();

  /// p. ej. "12+3".
  TextColumn get splitDetail => text().nullable()();
  BoolColumn get toFailure => boolean().withDefault(const Constant(false))();

  /// Carga externa en kg (mochila, garrafas). null = peso corporal.
  RealColumn get loadKg => real().nullable()();

  /// Variante de la progresión usada en la serie ("arquero", "pies
  /// elevados"; §18.4). null = la del plan.
  TextColumn get variant => text().nullable()();

  /// Repeticiones en reserva al terminar la serie (0 = no salía otra; §19.2).
  /// null = no se anotó.
  IntColumn get rir => integer().nullable().check(rir.isBetweenValues(0, 5))();
}

@DataClassName('FootballGameRow')
class FootballGames extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  IntColumn get format => integer().withDefault(const Constant(5))();
  IntColumn get minutes => integer()();
  IntColumn get steps => integer().nullable()();
  IntColumn get intensity => integer().nullable().check(intensity.isBetweenValues(1, 10))();
  IntColumn get fatigueAfter => integer().nullable().check(fatigueAfter.isBetweenValues(1, 10))();

  /// Hubo golpe o molestia. null = no se registró. Decide si el lunes baja.
  BoolColumn get knock => boolean().nullable()();
  TextColumn get notes => text().nullable()();

  /// Hidratación (§19.3): peso antes y después del partido y lo que se bebió
  /// durante. Con eso sale la tasa de sudor y cuánto reponer.
  RealColumn get weightBeforeKg => real().nullable()();
  RealColumn get weightAfterKg => real().nullable()();
  IntColumn get fluidMl => integer().nullable()();

  /// Del historial anterior a la app (§16.16), por confirmar: sin minutos.
  BoolColumn get imported => boolean().withDefault(const Constant(false))();
}

/// Macros por 1 unidad (`unit`) o por 100 g/ml (`per100`).
@DataClassName('FoodRow')
class Foods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get basis => textEnum<FoodBasis>()();

  /// Etiqueta de la unidad: "huevo", "lata", "scoop 25 g". Para `per100`: "g" o "ml".
  TextColumn get unitLabel => text().withDefault(const Constant('unidad'))();
  RealColumn get kcal => real()();
  RealColumn get protein => real()();
  RealColumn get carbs => real().withDefault(const Constant(0))();
  RealColumn get fat => real().withDefault(const Constant(0))();

  /// Cantidad por defecto al añadirlo (1 unidad, 100 g…).
  RealColumn get defaultQuantity => real().withDefault(const Constant(1))();

  /// Gramos de una unidad (1 huevo ≈ 55 g). Informativo.
  RealColumn get servingGrams => real().nullable()();

  /// `etiqueta` = verificado contra el empaque; `referencia` = promedio.
  TextColumn get source => textEnum<MacroSource>().withDefault(const Constant('referencia'))();

  /// Quién lo creó: la siembra, el usuario en el catálogo o una entrada libre
  /// guardada sola al registrar una comida.
  TextColumn get origin => textEnum<FoodOrigin>().withDefault(const Constant('usuario'))();

  /// Marcado para salir primero al buscar.
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();

  /// Huevos enteros por unidad o porción ("Huevos pericos (4)" = 4). Así el
  /// contador del día los cuenta aunque vengan dentro de un plato o un combo
  /// (§16.15). null = se deduce del nombre.
  RealColumn get eggsPerUnit => real().nullable()();
}

/// Combos de un toque: lo que se repite (batido, cena base…). Guardan
/// referencias al catálogo; los macros se calculan al registrarlos.
@DataClassName('MealTemplateRow')
class MealTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get slot => textEnum<MealSlot>().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

@DataClassName('MealTemplateItemRow')
class MealTemplateItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId => integer().references(MealTemplates, #id, onDelete: KeyAction.cascade)();
  IntColumn get foodId => integer().references(Foods, #id, onDelete: KeyAction.cascade)();
  RealColumn get quantity => real()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

@DataClassName('MealRow')
class Meals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  TextColumn get time => text().nullable()();
  TextColumn get slot => textEnum<MealSlot>()();
  TextColumn get notes => text().nullable()();
}

/// Los macros se copian al registrar (snapshot): editar el catálogo no
/// reescribe el historial. `foodId` null = entrada libre (bandeja, Rappi).
@DataClassName('MealItemRow')
class MealItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mealId => integer().references(Meals, #id, onDelete: KeyAction.cascade)();
  IntColumn get foodId => integer().nullable().references(Foods, #id, onDelete: KeyAction.setNull)();
  TextColumn get label => text()();
  RealColumn get quantity => real().nullable()();
  TextColumn get quantityUnit => text().nullable()();
  RealColumn get kcal => real()();
  RealColumn get protein => real()();
  RealColumn get carbs => real().withDefault(const Constant(0))();
  RealColumn get fat => real().withDefault(const Constant(0))();

  /// Si los macros copiados venían de una etiqueta verificada. null = entrada
  /// libre, donde la cifra es un cálculo a ojo.
  BoolColumn get sourceVerified => boolean().nullable()();
}

@DataClassName('BodyWeightRow')
class BodyWeights extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  RealColumn get kg => real()();
  BoolColumn get fasted => boolean().withDefault(const Constant(true))();

  /// Momento del pesaje (§18.10): 'ayunas', 'antesDormir', 'antesFutbol',
  /// 'despuesFutbol' u 'otro'. Solo 'ayunas' entra en el promedio semanal; el
  /// resto es referencia y alimenta la tasa de sudor. null en pesajes
  /// anteriores al esquema 17 (se lee de `fasted`).
  TextColumn get moment => text().nullable()();

  /// Hora del pesaje (`HH:mm`). null si no se anotó.
  TextColumn get time => text().nullable()();
}

@DataClassName('MeasurementRow')
class Measurements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  BoolColumn get fasted => boolean().withDefault(const Constant(true))();
  TextColumn get site => textEnum<MeasureSite>()();
  RealColumn get valueCm => real()();

  /// Hora de la toma (`HH:mm`): en ayunas a las 7:00 no es lo mismo que
  /// después de cenar (§16.10). null en tomas anteriores al esquema 14.
  TextColumn get time => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {date, site},
      ];
}

/// Fotos de progreso. Se guarda la ruta **relativa** al directorio de la app:
/// las absolutas se rompen al reinstalar o restaurar.
@DataClassName('ProgressPhotoRow')
class ProgressPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  TextColumn get angle => textEnum<PhotoAngle>()();
  TextColumn get relativePath => text()();
  BoolColumn get fasted => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
}

/// Ajustes de cada recordatorio. Una fila por tipo.
@DataClassName('ReminderRow')
class Reminders extends Table {
  TextColumn get kind => textEnum<ReminderKind>()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get hour => integer().nullable()();
  IntColumn get minute => integer().withDefault(const Constant(0))();

  /// Solo para el aviso de proteína: gramos por debajo de los cuales avisa.
  IntColumn get threshold => integer().nullable()();

  @override
  Set<Column> get primaryKey => {kind};
}

/// Días de comidas cerrados a mano: el usuario dice que ya no registra nada
/// más ese día aunque falte una comida principal (p. ej. no desayunó). Un día
/// con desayuno, almuerzo y cena se da por cerrado sin estar aquí.
@DataClassName('ClosedDayRow')
class ClosedDays extends Table {
  TextColumn get date => text()();

  @override
  Set<Column> get primaryKey => {date};
}

/// Pasos del día. Uno por fecha: registrar otra vez reemplaza. `source` dice de
/// dónde salió la cifra (hoy solo `manual`, leída del reloj o del teléfono).
@DataClassName('DailyStepsRow')
class DailySteps extends Table {
  TextColumn get date => text()();
  IntColumn get steps => integer().check(steps.isBiggerOrEqualValue(0))();
  TextColumn get source => text().withDefault(const Constant('manual'))();

  @override
  Set<Column> get primaryKey => {date};
}

/// Foto de referencia que el usuario guarda para un ejercicio (una captura de
/// un video, una foto propia bien hecha). Una por ejercicio; la clave es el
/// nombre sin mayúsculas ni tildes, así sirve también para la movilidad, que
/// no está en el catálogo de ejercicios. Ruta relativa, como las de progreso.
@DataClassName('ExercisePhotoRow')
class ExercisePhotos extends Table {
  TextColumn get nameKey => text()();
  TextColumn get relativePath => text()();

  @override
  Set<Column> get primaryKey => {nameKey};
}

/// Recordatorios que crea el usuario ("Ejercicios de cuello cada 3 días").
/// Los días se cuentan desde `lastDone` (o `startDate` si nunca se hizo).
@DataClassName('CustomReminderRow')
class CustomReminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 80)();
  TextColumn get note => text().nullable()();
  IntColumn get intervalDays => integer().check(intervalDays.isBetweenValues(1, 90))();
  IntColumn get hour => integer().check(hour.isBetweenValues(0, 23))();
  IntColumn get minute => integer().withDefault(const Constant(0))();
  TextColumn get startDate => text()();
  TextColumn get lastDone => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}

/// Horas en cama de la noche que termina en `date` (§19.3: ≥ 8 h). Una por
/// día; registrar otra vez reemplaza.
@DataClassName('SleepLogRow')
class SleepLogs extends Table {
  TextColumn get date => text()();
  RealColumn get hours => real().check(hours.isBetweenValues(0, 16))();

  @override
  Set<Column> get primaryKey => {date};
}

/// Registro de la mañana (§16.15, §19.6): pulso en reposo al despertar. El
/// peso en ayunas va en `body_weights` y las horas en cama en `sleep_logs`.
@DataClassName('MorningCheckRow')
class MorningChecks extends Table {
  TextColumn get date => text()();
  IntColumn get restingHr => integer().nullable().check(restingHr.isBetweenValues(25, 220))();

  @override
  Set<Column> get primaryKey => {date};
}

/// Molestia por zona y día, de 0 a 10 (en escaleras, §16.15). Una fila por
/// zona; 0 no se guarda.
@DataClassName('SorenessRow')
class SorenessLogs extends Table {
  TextColumn get date => text()();
  TextColumn get zone => text()();
  IntColumn get level => integer().check(level.isBetweenValues(0, 10))();

  @override
  Set<Column> get primaryKey => {date, zone};
}

/// Habilidades logradas de la hoja de ruta (§19.8): id de la habilidad y día
/// en que se cumplió el criterio.
@DataClassName('SkillAchievementRow')
class SkillAchievements extends Table {
  TextColumn get skill => text()();
  TextColumn get date => text()();

  @override
  Set<Column> get primaryKey => {skill};
}

/// Resultado de una prueba del test (§19.11): una serie máxima con técnica
/// estricta. `round`: 1 = test inicial, 2 = descarga, 3 = pruebas finales.
@DataClassName('FitnessTestRow')
class FitnessTests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  IntColumn get round => integer()();

  /// Id de la prueba (`pullups`, `broad_jump`…).
  TextColumn get item => text()();

  /// 'I' o 'D' en las pruebas por lado; null en el resto.
  TextColumn get side => text().nullable()();
  RealColumn get value => real()();

  /// true = limpia; false = con dudas.
  BoolColumn get clean => boolean().withDefault(const Constant(true))();
}

/// Peldaño actual de cada escalera de habilidad (§19.10) y desde cuándo.
@DataClassName('LadderStateRow')
class LadderStates extends Table {
  TextColumn get ladder => text()();
  IntColumn get step => integer()();
  TextColumn get since => text()();

  /// Último día con molestia lumbar: esa sesión no cuenta como limpia.
  TextColumn get lumbarOn => text().nullable()();

  /// Sesiones anteriores al cambio (incluidas las del mismo día) no cuentan.
  IntColumn get sessionsAfter => integer().withDefault(const Constant(0))();
  IntColumn get epoch => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {ladder};
}

class LadderEvents extends Table {
  TextColumn get eventKey => text()();
  TextColumn get ladder => text()();
  TextColumn get date => text()();
  IntColumn get step => integer()();
  @override
  Set<Column> get primaryKey => {eventKey, ladder};
}

/// Notas libres por semana (índice anclado a la fecha de inicio).
@DataClassName('WeekNoteRow')
class WeekNotes extends Table {
  IntColumn get weekIndex => integer()();
  TextColumn get body => text()();

  @override
  Set<Column> get primaryKey => {weekIndex};
}

/// Conversaciones locales de IA. `sourcesJson` y `sourcesHash` congelan la
/// fuente mostrada; la metadata local de guía tiene su propio JSON/hash y no
/// forma parte de la solicitud al gateway.
@DataClassName('AiConversationRow')
class AiConversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  TextColumn get rangeStart => text().nullable()();
  TextColumn get rangeEnd => text().nullable()();
  TextColumn get model => text()();
  IntColumn get contractVersion => integer()();
  TextColumn get sourcesJson => text()();
  TextColumn get sourcesHash => text().withLength(min: 64, max: 64)();
  TextColumn get guideContextJson => text().nullable()();
  TextColumn get guideContextHash => text().nullable()();
  IntColumn get createdAt => integer()();
}

/// Preguntas y respuestas verificadas. Las citas quedan ligadas al snapshot
/// por `conversationId`; borrar una conversación las elimina en cascada.
@DataClassName('AiMessageRow')
class AiMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId => integer().references(AiConversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
  TextColumn get messageText => text()();
  TextColumn get citationsJson => text()();
  TextColumn get model => text()();
  IntColumn get contractVersion => integer()();
  IntColumn get createdAt => integer()();
}
