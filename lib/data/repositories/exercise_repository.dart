import 'package:drift/drift.dart';

import '../database.dart';

class ExerciseRepository {
  ExerciseRepository(this.db);

  final AppDatabase db;

  Stream<List<ExerciseRow>> watchAll() =>
      (db.select(db.exercises)..orderBy([(t) => OrderingTerm(expression: t.name.collate(Collate.noCase))]))
          .watch();

  /// Devuelve el id del ejercicio con ese nombre (sin distinguir mayúsculas)
  /// o lo crea. Normaliza espacios.
  Future<int> getOrCreate(String rawName) async {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw ArgumentError('Nombre de ejercicio vacío');
    final existing = await (db.select(db.exercises)
          ..where((t) => t.name.lower().equals(name.toLowerCase()))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    return db.into(db.exercises).insert(ExercisesCompanion.insert(name: name));
  }

  Future<Map<int, String>> namesById() async =>
      {for (final e in await db.select(db.exercises).get()) e.id: e.name};

  Future<void> rename(int id, String name) =>
      (db.update(db.exercises)..where((t) => t.id.equals(id))).write(ExercisesCompanion(name: Value(name.trim())));
}
