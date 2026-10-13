/// ¿Cómo llega el cuerpo hoy? (§19.17). Una sola función, `readiness`, que
/// usan Hoy, el aviso de la noche y el informe: verde = el plan, amarillo =
/// recuperación activa, rojo = solo descanso. Lógica pura.
///
/// Las ventanas van por días de calendario, no por horas: los partidos se
/// guardan sin hora. "Últimos 3 días" = anteayer, ayer y hoy; "hoy y ayer" =
/// los dos últimos. No son ventanas exactas de 48 y 36 horas.
///
/// Los umbrales salen del traspaso; son reglas de entrenamiento, no una
/// valoración médica.
library;

import 'dates.dart';
import 'format.dart';
import 'recovery.dart' show LoadItem;

enum ReadinessLevel { green, yellow, red }

enum SuggestedAction { trainAsPlanned, recoveryActive, restOnly }

/// Carga de los últimos 3 días a partir de la cual toca recuperación activa.
const readinessLoad3Days = 900;

/// Partidos entre ayer y hoy a partir de los cuales toca recuperación activa.
const readinessGames2Days = 2;

/// Relación aguda:crónica (7 días ÷ 28 días) por encima de la cual toca bajar.
const readinessAcuteChronic = 1.5;

/// Días de historial mínimos para usar la relación aguda:crónica.
const readinessMinHistoryDays = 21;

/// Lecturas de pulso necesarias para tener una base, y cuántas se usan.
const readinessHrBaseMin = 7;
const readinessHrBaseMax = 14;

const readinessHrYellow = 5;
const readinessHrRed = 10;
const readinessStairsYellow = 3;
const readinessStairsRed = 5;
const readinessSorenessYellow = 6;
const readinessHardEffort = 8;
const readinessShortSleepAfterHard = 7.0;
const readinessShortSleep = 6.0;

class ReadinessInput {
  const ReadinessInput({
    required this.today,
    required this.load,
    this.stairs,
    this.kneeSoreness,
    this.muscleSoreness,
    this.ill,
    this.restingHrToday,
    this.restingHrBaseline = const [],
    this.sleepHours,
    this.testOrAttemptToday = false,
  });

  final DateTime today;

  /// Sesiones y partidos que cuentan como carga (sin movilidad, recuperación,
  /// importado ni test de condición).
  final List<LoadItem> load;

  /// Molestia al bajar escaleras, 0–10. null = no se anotó.
  final int? stairs;

  /// Molestia registrada por zona Rodilla; no prueba escaleras.
  final int? kneeSoreness;

  /// Dolor muscular general, 0–10. null = no se anotó.
  final int? muscleSoreness;

  /// Enfermo, fiebre o dolor agudo. null = no se anotó.
  final bool? ill;

  final int? restingHrToday;

  /// Lecturas válidas anteriores a hoy, la más reciente primero.
  final List<int> restingHrBaseline;

  /// Horas dormidas anotadas hoy (si la siesta se anotó junto, cuenta).
  final double? sleepHours;

  /// Hoy hay test o intento de récord.
  final bool testOrAttemptToday;
}

class ReadinessAdvice {
  const ReadinessAdvice({
    required this.level,
    required this.reasons,
    required this.missing,
    required this.load3Days,
    this.acuteChronic,
    this.testOrAttemptToday = false,
  });

  final ReadinessLevel level;

  /// Por qué, con datos: "Carga de los últimos 3 días: 1.410 (sáb 300 · …)".
  final List<String> reasons;

  /// Lo que faltó para decidir: "Pulso: sin dato".
  final List<String> missing;

  final int load3Days;

  /// null si hay menos de 21 días de historial.
  final double? acuteChronic;
  final bool testOrAttemptToday;

  SuggestedAction get action => switch (level) {
        ReadinessLevel.green => SuggestedAction.trainAsPlanned,
        ReadinessLevel.yellow => SuggestedAction.recoveryActive,
        ReadinessLevel.red => SuggestedAction.restOnly,
      };

  /// Con test o intento hoy y un día que no es verde, se propone moverlo.
  bool get moveTestToTomorrow =>
      testOrAttemptToday && level != ReadinessLevel.green;

  /// Verde sin datos que falten. Un verde con huecos no es "estás recuperado".
  bool get confident => missing.isEmpty;

  String get title => switch (level) {
        ReadinessLevel.green => confident
            ? 'Hoy: el plan normal'
            : 'Hoy: el plan normal, con datos incompletos',
        ReadinessLevel.yellow => 'Hoy: recuperación activa',
        ReadinessLevel.red => 'Hoy: solo descanso',
      };

  /// Qué hacer, en una línea. El rojo no propone la activación del amarillo.
  String get advice => switch (level) {
        ReadinessLevel.green => confident
            ? 'Sin señales de carga alta.'
            : 'Sin señales de carga alta en lo anotado; falta ${missing.join(', ').toLowerCase()}.',
        ReadinessLevel.yellow =>
          'Movilidad, activación suave y soltar piernas, a 3–4/10. Nunca al fallo.',
        ReadinessLevel.red =>
          'Solo isométricos de rodilla suaves y movilidad. Si es enfermedad o dolor agudo, descansa.',
      };
}

ReadinessAdvice readiness(ReadinessInput i) {
  final d0 = dateOnly(i.today);
  final red = <String>[];
  final yellow = <String>[];
  final missing = <String>[];

  int dayLoad(DateTime d) =>
      i.load.where((x) => dateOnly(x.date) == d).fold(0, (a, x) => a + x.load);

  // Últimos 3 días, en orden.
  final window = [for (var k = 2; k >= 0; k--) addDays(d0, -k)];
  final windowItems = [
    for (final d in window)
      for (final x in i.load)
        if (dateOnly(x.date) == d) x,
  ];
  final load3 = windowItems.fold(0, (a, x) => a + x.load);
  if (load3 >= readinessLoad3Days) {
    final detail = windowItems
        .map((x) => '${weekdayShort(x.date.weekday)} ${fmtInt(x.load)}')
        .join(' · ');
    yellow.add('Carga de los últimos 3 días: ${fmtInt(load3)} ($detail)');
  }

  final games = i.load.where((x) =>
      x.isFootball &&
      !dateOnly(x.date).isBefore(addDays(d0, -1)) &&
      !dateOnly(x.date).isAfter(d0));
  if (games.length >= readinessGames2Days) {
    yellow.add('${games.length} partidos entre ayer y hoy');
  }

  // Aguda:crónica, solo con historial suficiente.
  double? ratio;
  if (i.load.isNotEmpty) {
    final first = i.load
        .map((x) => dateOnly(x.date))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final historyDays = daysBetween(first, d0) + 1;
    if (historyDays >= readinessMinHistoryDays) {
      var acute = 0;
      var chronic = 0;
      for (var k = 0; k < 28; k++) {
        final l = dayLoad(addDays(d0, -k));
        chronic += l;
        if (k < 7) acute += l;
      }
      if (chronic > 0) {
        ratio = (acute / 7) / (chronic / 28);
        if (ratio > readinessAcuteChronic) {
          yellow.add(
              'Carga aguda:crónica ${fmtDec(ratio, decimals: 2)} (7 días frente a 28)');
        }
      }
    }
  }

  // Esfuerzo alto ayer y poco sueño.
  final yesterday = addDays(d0, -1);
  final hardYesterday = i.load
      .where((x) =>
          dateOnly(x.date) == yesterday &&
          (x.effort ?? 0) >= readinessHardEffort)
      .map((x) => x.effort!)
      .fold<int?>(null, (a, e) => a == null || e > a ? e : a);
  final sleep = i.sleepHours;
  if (sleep == null) {
    missing.add('Sueño: sin dato');
  } else {
    if (hardYesterday != null && sleep < readinessShortSleepAfterHard) {
      yellow.add('Ayer esfuerzo $hardYesterday y ${fmtDec(sleep)} h de sueño');
    } else if (sleep < readinessShortSleep) {
      yellow.add('Dormiste ${fmtDec(sleep)} h');
    }
  }

  // Pulso contra la base.
  final base = i.restingHrBaseline.take(readinessHrBaseMax).toList();
  if (i.restingHrToday == null) {
    missing.add('Pulso: sin dato');
  } else if (base.length < readinessHrBaseMin) {
    missing.add(
        'Pulso: sin base (${base.length} de $readinessHrBaseMin lecturas)');
  } else {
    final mean = base.reduce((a, b) => a + b) / base.length;
    final rise = i.restingHrToday! - mean;
    final text =
        'Pulso en reposo ${i.restingHrToday}: +${rise.round()} sobre tu base (${mean.round()})';
    if (rise >= readinessHrRed) {
      red.add(text);
    } else if (rise >= readinessHrYellow) {
      yellow.add(text);
    }
  }

  final stairs = i.stairs;
  if (stairs == null) {
    missing.add('Escaleras: sin dato');
  } else if (stairs >= readinessStairsRed) {
    red.add('Rodilla en escaleras $stairs/10');
  } else if (stairs >= readinessStairsYellow) {
    yellow.add('Rodilla en escaleras $stairs/10');
  }

  // Conserva la severidad del registro legado con su propia procedencia.
  // Sus umbrales existentes siguen vigentes; nunca completa el dato escaleras.
  if (i.kneeSoreness case final pain?) {
    if (pain >= readinessStairsRed) {
      red.add('Dolor anotado en Rodilla $pain/10');
    } else if (pain >= readinessStairsYellow) {
      yellow.add('Dolor anotado en Rodilla $pain/10');
    }
  }

  final sore = i.muscleSoreness;
  if (sore == null) {
    missing.add('Dolor muscular: sin dato');
  } else if (sore >= readinessSorenessYellow) {
    yellow.add('Dolor muscular $sore/10');
  }

  if (i.ill == true) red.add('Marcaste enfermo, fiebre o dolor agudo');

  final level = red.isNotEmpty
      ? ReadinessLevel.red
      : yellow.isNotEmpty
          ? ReadinessLevel.yellow
          : ReadinessLevel.green;
  return ReadinessAdvice(
    level: level,
    reasons: [...red, ...yellow],
    missing: missing,
    load3Days: load3,
    acuteChronic: ratio,
    testOrAttemptToday: i.testOrAttemptToday,
  );
}

/// Resumen de la semana para el informe.
class ReadinessWeek {
  const ReadinessWeek({
    required this.proposed,
    required this.accepted,
    required this.trainedAnyway,
    required this.days,
    required this.maxLoad3Days,
    this.acuteChronic,
  });

  /// Días amarillos o rojos.
  final int proposed;

  /// De esos, con la recuperación activa guardada.
  final int accepted;

  /// De esos, con "Entrenar igual".
  final int trainedAnyway;

  /// Cada día amarillo o rojo con sus razones.
  final List<(DateTime, ReadinessAdvice)> days;
  final int maxLoad3Days;

  /// La del último día de la semana; null con menos de 21 días de historial.
  final double? acuteChronic;
}

/// Sección "Recuperación" del informe semanal (§19.17). Vacía si no hubo
/// días amarillos ni rojos y la carga no subió.
List<String> readinessReportLines(ReadinessWeek w) {
  if (w.proposed == 0 && w.maxLoad3Days < readinessLoad3Days) return const [];
  return [
    'Días de recuperación propuestos: ${w.proposed} · aceptados: ${w.accepted} · entrenó igual: ${w.trainedAnyway}',
    'Carga máxima de 3 días: ${fmtInt(w.maxLoad3Days)}'
        '${w.acuteChronic == null ? ' · aguda:crónica sin historial suficiente' : ' · aguda:crónica ${fmtDec(w.acuteChronic!, decimals: 2)}'}',
    for (final (day, a) in w.days)
      '${weekdayShort(day.weekday)} ${formatShort(day)} · ${a.level == ReadinessLevel.red ? 'rojo' : 'amarillo'}: '
          '${a.reasons.join('; ')}',
  ];
}

/// La noche anterior (22:00): con la carga de ayer y hoy ya por encima del
/// umbral, mañana probablemente toca recuperación activa. null si no.
String? readinessEveningNotice(List<LoadItem> load, DateTime today) {
  final d0 = dateOnly(today);
  final from = addDays(d0, -1);
  final total = load
      .where((x) =>
          !dateOnly(x.date).isBefore(from) && !dateOnly(x.date).isAfter(d0))
      .fold(0, (a, x) => a + x.load);
  if (total < readinessLoad3Days) return null;
  return 'Carga de ayer y hoy: ${fmtInt(total)}. Mañana probablemente toca recuperación activa. '
      'Duerme 8 h; el test se decide con el registro de la mañana.';
}
