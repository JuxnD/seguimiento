import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/report/report_input.dart';
import '../../domain/goal_history.dart' show GoalMetric, GoalOrigin;
import '../database.dart';
import 'goal_repository.dart';

/// Origen del perfil (plan 022, esquema 23). Se guarda tal cual en SQLite.
abstract final class ProfileOrigin {
  /// Instalación nueva: el alta la hace quien la usa.
  static const newInstall = 'new';

  /// Base que ya existía al migrar al 23: no se infiere quién es.
  static const legacyUnknown = 'legacyUnknown';

  static const values = {newInstall, legacyUnknown};
}

/// Estado del alta.
abstract final class SetupState {
  static const pending = 'pending';
  static const ready = 'ready';

  static const values = {pending, ready};
}

/// Origen/estado del alta que no cumple el contrato. El mensaje se muestra.
class InvalidSetupException implements Exception {
  InvalidSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Alta inválida o incompleta al confirmar. El mensaje se muestra.
class SetupValidationException implements Exception {
  SetupValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Estado del alta leído del perfil. Contrato para AppEntry, restauración y
/// el cierre 012.
class SetupStatus {
  const SetupStatus({required this.origin, required this.state, this.confirmedAt, this.handoffConsentAt});

  /// [ProfileOrigin].
  final String origin;

  /// [SetupState].
  final String state;

  /// Momento real de la confirmación del alta; null si no la hubo.
  final DateTime? confirmedAt;

  /// Consentimiento fechado para las correcciones del traspaso original.
  final DateTime? handoffConsentAt;

  bool get pending => state == SetupState.pending;
  bool get ready => state == SetupState.ready;
  bool get isNewInstall => origin == ProfileOrigin.newInstall;

  /// Valida origen, estado y fechas. Lanza [InvalidSetupException]; nunca
  /// corrige ni infiere.
  static SetupStatus parse(ProfileRow p) {
    if (!ProfileOrigin.values.contains(p.profileOrigin)) {
      throw InvalidSetupException('Origen de perfil desconocido: "${p.profileOrigin}".');
    }
    if (!SetupState.values.contains(p.setupState)) {
      throw InvalidSetupException('Estado de alta desconocido: "${p.setupState}".');
    }
    DateTime? time(String? raw, String what) {
      if (raw == null) return null;
      final t = DateTime.tryParse(raw);
      if (t == null) throw InvalidSetupException('Fecha de $what inválida: "$raw".');
      return t;
    }

    final confirmed = time(p.setupConfirmedAt, 'confirmación del alta');
    final consent = time(p.handoffConsentAt, 'consentimiento del traspaso');
    if (p.profileOrigin == ProfileOrigin.legacyUnknown && (p.setupState != SetupState.ready || confirmed != null)) {
      throw InvalidSetupException('Un perfil existente antes del alta sólo puede estar listo y sin confirmación.');
    }
    if (p.profileOrigin == ProfileOrigin.newInstall) {
      if (p.setupState == SetupState.pending && confirmed != null) {
        throw InvalidSetupException('Un alta pendiente no puede tener fecha de confirmación.');
      }
      if (p.setupState == SetupState.ready && confirmed == null) {
        throw InvalidSetupException('Un alta lista necesita su fecha de confirmación.');
      }
    }
    return SetupStatus(origin: p.profileOrigin, state: p.setupState, confirmedAt: confirmed, handoffConsentAt: consent);
  }
}

/// Lo que se elige en el alta. Las metas nutricionales null son una decisión
/// "sin meta" (también con «Más adelante»), no un valor por defecto.
class SetupDraft {
  SetupDraft({
    required this.startDate,
    this.heightCm,
    this.birthDate,
    this.stepsTarget = 5000,
    this.proteinMin,
    this.proteinPreferred,
    this.kcalWeekly,
    this.kcalFootball,
    this.kcalFloor,
  });

  /// Inicio del programa (ancla de las semanas). No es la vigencia de las
  /// metas: ésas rigen desde la confirmación.
  DateTime startDate;
  double? heightCm;
  DateTime? birthDate;
  int stepsTarget;
  int? proteinMin;

  /// Tope del rango de proteína (`proteinaMax`).
  int? proteinPreferred;
  int? kcalWeekly;

  /// null = la misma de entre semana (si ésa existe).
  int? kcalFootball;
  int? kcalFloor;

  /// «Más adelante»: ninguna meta nutricional.
  void clearNutrition() => proteinMin = proteinPreferred = kcalWeekly = kcalFootball = kcalFloor = null;

  /// Primer problema, o null.
  String? problem(DateTime today) {
    final d = dateOnly(today);
    if (dateOnly(startDate).isAfter(d)) return 'La fecha de inicio no puede ser futura.';
    if (dateOnly(startDate).isBefore(DateTime(2000))) return 'La fecha de inicio no es válida.';
    if (birthDate case final b? when !dateOnly(b).isBefore(d) || b.isBefore(DateTime(1900))) {
      return 'La fecha de nacimiento no es válida.';
    }
    if (heightCm case final h? when !h.isFinite || h < 50 || h > 260) return 'La estatura va de 50 a 260 cm.';
    if (stepsTarget <= 0 || stepsTarget > 100000) return 'Los pasos diarios van de 1 a 100.000.';
    bool bad(int? v, int max) => v != null && (v <= 0 || v > max);
    if (bad(proteinMin, 500) || bad(proteinPreferred, 500)) return 'La proteína va de 1 a 500 g.';
    if (bad(kcalWeekly, 10000) || bad(kcalFootball, 10000) || bad(kcalFloor, 10000)) {
      return 'Las kcal van de 1 a 10.000.';
    }
    if (proteinMin != null && proteinPreferred != null && proteinMin! > proteinPreferred!) {
      return 'La proteína mínima no puede ser mayor que la preferida.';
    }
    if (kcalFloor != null && kcalWeekly != null && kcalFloor! > kcalWeekly!) {
      return 'El piso de kcal no puede ser mayor que las kcal entre semana.';
    }
    return null;
  }
}

/// Tablas que no son registros personales: catálogo y combos compartidos,
/// ajustes de avisos y el propio perfil. Todo lo demás (también lo que se
/// añada después) cuenta como personal.
const sharedReferenceTables = {
  'profiles',
  'exercises',
  'foods',
  'catalog_patches',
  'meal_templates',
  'meal_template_items',
  'reminders',
};

/// Tablas personales con filas. Vacío en un alta pendiente.
Future<List<String>> personalTablesWithRows(AppDatabase db) async => [
      for (final t in db.allTables)
        if (!sharedReferenceTables.contains(t.actualTableName) &&
            (await db.customSelect('select 1 from "${t.actualTableName}" limit 1').get()).isNotEmpty)
          t.actualTableName,
    ];

/// Contrato común del alta para la base abierta y para un respaldo antes de
/// restaurarlo: origen/estado válidos y, si está pendiente, sin registros
/// personales ni metas aceptadas. Lanza [InvalidSetupException].
Future<SetupStatus> validateSetup(AppDatabase db) async {
  final row = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();
  final status = SetupStatus.parse(row);
  if (status.pending) {
    final personal = await personalTablesWithRows(db);
    if (personal.isNotEmpty) {
      throw InvalidSetupException('Un alta pendiente no puede traer registros personales (${personal.join(', ')}).');
    }
  }
  return status;
}

class ProfileRepository {
  ProfileRepository(this.db);

  final AppDatabase db;

  Stream<ProfileRow> watch() => (db.select(db.profiles)..where((t) => t.id.equals(1))).watchSingle();

  Future<ProfileRow> get() => (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();

  /// Estado del alta; un valor inválido llega como error del stream.
  Stream<SetupStatus> watchSetup() => watch().map(SetupStatus.parse);

  Future<SetupStatus> setupStatus() async => SetupStatus.parse(await get());

  /// Confirma el alta en una sola transacción: valida que siga pendiente y sin
  /// registros personales, escribe el perfil, acepta las seis metas iniciales
  /// (también las null y las iguales al valor de ejemplo) con vigencia desde
  /// la confirmación real y deja el alta lista. Si algo falla no queda nada.
  /// Devuelve false si ya estaba lista (confirmar dos veces no duplica).
  Future<bool> confirmSetup(SetupDraft d, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final today = dateOnly(at);
    if (d.problem(today) case final p?) throw SetupValidationException(p);
    return db.transaction(() async {
      final status = await validateSetup(db);
      if (status.ready) return false;
      if ((await db.select(db.goalVersions).get()).isNotEmpty) {
        throw InvalidSetupException('Un alta pendiente no puede tener metas aceptadas.');
      }
      await (db.update(db.profiles)..where((t) => t.id.equals(1))).write(ProfilesCompanion(
        startDate: Value(dayKey(d.startDate)),
        heightCm: Value(d.heightCm),
        birthDate: Value(d.birthDate == null ? null : dayKey(d.birthDate!)),
        stepsTarget: Value(d.stepsTarget),
        // Sin meta: la proyección interna del perfil se conserva; la decisión
        // está en goal_versions (value null conocido).
        proteinMin: d.proteinMin == null ? const Value.absent() : Value(d.proteinMin!),
        proteinMax: d.proteinPreferred == null ? const Value.absent() : Value(d.proteinPreferred!),
        kcalTarget: d.kcalWeekly == null ? const Value.absent() : Value(d.kcalWeekly!),
        kcalFloor: d.kcalFloor == null ? const Value.absent() : Value(d.kcalFloor!),
        kcalTargetFootball: Value(d.kcalFootball),
        setupState: const Value(SetupState.ready),
        setupConfirmedAt: Value(at.toIso8601String()),
      ));
      final accepted = <GoalMetric, int?>{
        GoalMetric.pasos: d.stepsTarget,
        GoalMetric.proteinaMin: d.proteinMin,
        GoalMetric.proteinaMax: d.proteinPreferred,
        GoalMetric.kcal: d.kcalWeekly,
        GoalMetric.kcalFutbol: d.kcalFootball,
        GoalMetric.kcalFloor: d.kcalFloor,
      };
      for (final e in accepted.entries) {
        await db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
              metric: e.key.name,
              value: Value(e.value?.toDouble()),
              effectiveFrom: Value(dayKey(today)),
              acceptedAt: dayKey(today),
              origin: GoalOrigin.inicio,
              reason: const Value('Alta'),
            ));
      }
      return true;
    });
  }

  /// Registra el consentimiento explícito para las correcciones del traspaso
  /// original. Fechado; no cambia el alta ni aplica nada.
  Future<void> recordHandoffConsent({DateTime? now}) => (db.update(db.profiles)..where((t) => t.id.equals(1)))
      .write(ProfilesCompanion(handoffConsentAt: Value((now ?? DateTime.now()).toIso8601String())));

  /// Guarda el perfil; cada meta que cambie queda con su vigencia desde hoy
  /// (plan 009). El pasado se sigue evaluando con la meta que regía.
  Future<void> save(ProfilesCompanion data) => GoalRepository(db).updateProfile(data, origin: GoalOrigin.perfil);

  Stream<String?> watchWeekNote(int weekIndex) =>
      (db.select(db.weekNotes)..where((t) => t.weekIndex.equals(weekIndex))).watchSingleOrNull().map((r) => r?.body);

  Future<void> saveWeekNote(int weekIndex, String body) async {
    if (body.trim().isEmpty) {
      await (db.delete(db.weekNotes)..where((t) => t.weekIndex.equals(weekIndex))).go();
    } else {
      await db.into(db.weekNotes).insertOnConflictUpdate(WeekNotesCompanion.insert(
            weekIndex: Value(weekIndex),
            body: body.trim(),
          ));
    }
  }
}

extension ProfileRowX on ProfileRow {
  DateTime get programStart => parseDay(startDate);

  Targets get targets => Targets(
        proteinMin: proteinMin,
        proteinMax: proteinMax,
        kcalTarget: kcalTarget,
        kcalTargetFootball: kcalTargetFootball,
        kcalFloor: kcalFloor,
        minWarmupSec: minWarmupSec,
        measureIntervalDays: measureIntervalDays,
        lengthUnit: lengthUnit,
        stepsTarget: stepsTarget,
      );
}
