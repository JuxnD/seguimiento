/// Explicit timer identity; never inferred from exercise labels or notes.
enum TimerProfile { tabata, running1515 }

/// Frozen prescription. A legacy snapshot without this object keeps the
/// historical Tabata defaults; a partially specified new one is invalid.
class TimerPrescription {
  const TimerPrescription({
    required this.profile,
    required this.workSec,
    required this.restSec,
    required this.intervals,
    required this.betweenBlocksSec,
    required this.includeFinalRest,
    this.footballFreeConfirmed,
  });

  const TimerPrescription.running1515()
      : profile = TimerProfile.running1515,
        workSec = 15,
        restSec = 15,
        intervals = 16,
        betweenBlocksSec = 0,
        includeFinalRest = true,
        footballFreeConfirmed = true;

  final TimerProfile profile;
  final int workSec, restSec, intervals, betweenBlocksSec;
  final bool includeFinalRest;
  final bool? footballFreeConfirmed;

  void validate({required int blocks}) {
    if (blocks <= 0 || workSec <= 0 || restSec < 0 || intervals <= 0 || betweenBlocksSec < 0) {
      throw const FormatException('Duración de intervalos inválida');
    }
    if (profile == TimerProfile.running1515 &&
        (blocks != 2 || workSec != 15 || restSec != 15 || intervals != 16 ||
            betweenBlocksSec != 0 || !includeFinalRest || footballFreeConfirmed != true)) {
      throw const FormatException('Prescripción de carrera 15/15 inválida o sin confirmación');
    }
  }

  Map<String, Object?> toJson() => {
        'profile': profile.name,
        'workSec': workSec,
        'restSec': restSec,
        'intervals': intervals,
        'betweenBlocksSec': betweenBlocksSec,
        'includeFinalRest': includeFinalRest,
        'footballFreeConfirmed': footballFreeConfirmed,
      };

  static TimerPrescription? fromJson(Map<String, Object?> json, {required int blocks, required String mode}) {
    const keys = ['profile', 'workSec', 'restSec', 'intervals', 'betweenBlocksSec',
      'includeFinalRest', 'footballFreeConfirmed'];
    if (!keys.any(json.containsKey)) {
      if (mode == 'running1515') throw const FormatException('Falta la prescripción de carrera');
      return null;
    }
    final value = TimerPrescription(
      profile: TimerProfile.values.byName(json['profile']! as String),
      workSec: json['workSec']! as int,
      restSec: json['restSec']! as int,
      intervals: json['intervals']! as int,
      betweenBlocksSec: json['betweenBlocksSec']! as int,
      includeFinalRest: json['includeFinalRest']! as bool,
      footballFreeConfirmed: json['footballFreeConfirmed'] as bool?,
    );
    value.validate(blocks: blocks);
    if (mode != value.profile.name) throw const FormatException('Perfil y modo no coinciden');
    return value;
  }
}
