import 'dates.dart';
import 'enums.dart';
import 'session_math.dart';

/// Seconds per round, never cumulative stopwatch marks. Work excludes rest;
/// lap includes it. Missing rest is not interpreted as zero.
enum TimingBasis { work, lap }

class RoundTimingEvidence {
  RoundTimingEvidence(
      {required this.sessionId,
      required this.date,
      required this.type,
      required this.basis,
      required List<int> durationsSec,
      this.rounds,
      this.planDayId,
      this.mode,
      this.exerciseProtocol,
      this.imported = false,
      this.estimated = false,
      this.incomplete = false})
      : durationsSec = List.unmodifiable(durationsSec);
  final int? sessionId;
  final DateTime date;
  final SessionType type;
  final TimingBasis basis;
  final List<int> durationsSec;
  final int? rounds;
  final int? planDayId;
  final String? mode;

  /// Sorted dose/variant/load signature of the actually recorded exercises.
  /// null is unknown, never a matching protocol by default.
  final String? exerciseProtocol;
  final bool imported, estimated, incomplete;
  int? get meanDurationSec => durationsSec.any((x) => x <= 0) ? null : meanSec(durationsSec);
  bool get eligible => !imported && !estimated && !incomplete;

  /// Unknown plan identity may be displayed but does not establish matching
  /// exercise/dose protocols. The caller may still report observed rounds.
  bool comparableTo(RoundTimingEvidence other) =>
      eligible &&
      other.eligible &&
      type == other.type &&
      mode == other.mode &&
      planDayId != null &&
      planDayId == other.planDayId &&
      exerciseProtocol != null &&
      exerciseProtocol == other.exerciseProtocol &&
      basis == other.basis;
}

class StrengthSetEvidence {
  const StrengthSetEvidence(
      {required this.reps,
      this.rir,
      this.split = false,
      this.splitDetail,
      this.toFailure = false,
      this.loadKg,
      this.variant});
  final int reps;
  final int? rir;
  final bool split, toFailure;
  final String? splitDetail, variant;
  final double? loadKg;
}

class StrengthSessionEvidence {
  StrengthSessionEvidence(
      {required this.sessionId,
      required this.date,
      required this.type,
      required this.exercise,
      required List<StrengthSetEvidence> sets,
      this.planDayId,
      this.incomplete = false,
      this.imported = false})
      : sets = List.unmodifiable(sets);
  final int sessionId;
  final DateTime date;
  final SessionType type;
  final String exercise;
  final List<StrengthSetEvidence> sets;
  final int? planDayId;
  final bool incomplete, imported;

  /// SQLite does not store side on strength sets. Bilateral identity cannot
  /// be reconstructed from ordering and must not be asserted by this DTO.
  bool usableBefore(DateTime date, {bool perSide = false}) =>
      !perSide &&
      !incomplete &&
      !imported &&
      this.date.isBefore(dateOnly(date)) &&
      sets.isNotEmpty &&
      sets.every((s) =>
          !s.split &&
          !s.toFailure &&
          s.reps >= 0 &&
          (s.rir == null || s.rir! > 0) &&
          s.variant == sets.first.variant &&
          s.loadKg == sets.first.loadKg);
}
