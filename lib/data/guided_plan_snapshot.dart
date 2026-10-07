import 'repositories/plan_repository.dart';
import '../domain/enums.dart';

/// Snapshot del día efectivo, independiente de cambios posteriores de escalera.
Map<String, Object?> freezeGuidedDay(PlanDayDraft day) => {
      'weekday': day.weekday,
      'type': day.type.name,
      'rounds': day.targetRounds,
      'rest': day.restBetweenRoundsSec,
      'notes': day.notes,
      'coreEpochs': day.coreEpochs,
      'exercises': [
        for (final e in day.exercises)
          {
            'name': e.name,
            'sets': e.sets,
            'repsMin': e.repsMin,
            'repsMax': e.repsMax,
            'restSec': e.restSec,
            'restSecMax': e.restSecMax,
            'grip': e.grip,
            'block': e.block,
            'variant': e.variant,
            'holdSecMin': e.holdSecMin,
            'holdSecMax': e.holdSecMax,
            'perSide': e.perSide,
            'rirMin': e.rirMin,
            'rirMax': e.rirMax,
            'notes': e.notes,
            'supersetGroup': e.supersetGroup,
          }
      ],
    };

PlanDayDraft thawGuidedDay(Map<String, Object?> j) => PlanDayDraft(
      weekday: j['weekday']! as int,
      type: DayType.values.byName(j['type']! as String),
      targetRounds: j['rounds'] as int?,
      restBetweenRoundsSec: j['rest'] as int?,
      notes: j['notes'] as String?,
      coreEpochs: (j['coreEpochs'] as Map?)?.cast<String, String>() ?? const {},
      exercises: [for (final raw in j['exercises']! as List) _exercise((raw as Map).cast<String, Object?>())],
    );
PlanExerciseDraft _exercise(Map<String, Object?> j) => PlanExerciseDraft(
      name: j['name'] as String,
      sets: j['sets'] as int?,
      repsMin: j['repsMin'] as int?,
      repsMax: j['repsMax'] as int?,
      restSec: j['restSec'] as int?,
      restSecMax: j['restSecMax'] as int?,
      grip: j['grip'] as String?,
      block: j['block'] as String?,
      variant: j['variant'] as String?,
      holdSecMin: j['holdSecMin'] as int?,
      holdSecMax: j['holdSecMax'] as int?,
      perSide: j['perSide'] as bool,
      rirMin: j['rirMin'] as int?,
      rirMax: j['rirMax'] as int?,
      notes: j['notes'] as String?,
      supersetGroup: j['supersetGroup'] as String?,
    );
