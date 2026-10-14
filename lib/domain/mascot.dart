/// Rayito, la mascota de My Prime (plan 049): el rayo de la marca, con cara y
/// sin cuerpo, que crece con la racha de constancia. Lógica pura: recibe la
/// racha y cómo va el día; no lee la base.
library;

/// Fases por días de racha. El orden es el de crecimiento.
enum MascotPhase {
  dormido(0, 'Dormido'),
  despierto(1, 'Despierto'),
  cargado(3, 'Cargado'),
  energizado(7, 'Energizado'),
  tormenta(14, 'Tormenta'),
  super_(21, 'Súper'),
  prime(30, 'Prime'),
  leyenda(60, 'Leyenda');

  const MascotPhase(this.fromDays, this.label);

  /// Días de racha desde los que empieza la fase.
  final int fromDays;
  final String label;

  /// Nivel de 1 a [levels] que ve el usuario (plan 052): el nombre de la
  /// mascota es sólo «Rayito»; la fase no se muestra con nombre propio.
  int get level => index + 1;
  static const levels = 8;

  /// La fase siguiente, o null en la última.
  MascotPhase? get next => index + 1 < MascotPhase.values.length
      ? MascotPhase.values[index + 1]
      : null;
}

/// La fase que corresponde a `streak` días de racha.
MascotPhase mascotPhase(int streak) {
  var phase = MascotPhase.dormido;
  for (final p in MascotPhase.values) {
    if (streak >= p.fromDays) phase = p;
  }
  return phase;
}

/// Días que faltan para la fase siguiente; null en la última.
int? daysToNextPhase(int streak) {
  final next = mascotPhase(streak).next;
  return next == null ? null : next.fromDays - streak;
}

/// Cómo está Rayito hoy. La cara cambia; la fase no.
enum MascotMood {
  /// Hoy ya hay un registro de actividad.
  contento,

  /// Hoy todavía no hay registro y hay racha que cuidar.
  atento,

  /// El check de la mañana pidió descanso o recuperación (032): no presiona.
  sereno,

  /// Sin racha: dormido, espera el primer registro.
  dormido,
}

MascotMood mascotMood({
  required int streak,
  required bool activeToday,
  required bool restAdvised,
}) {
  if (activeToday) return MascotMood.contento;
  if (restAdvised) return MascotMood.sereno;
  if (streak == 0) return MascotMood.dormido;
  return MascotMood.atento;
}
