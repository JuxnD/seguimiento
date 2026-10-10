import 'progress_metrics.dart';

class RadarProfile {
  RadarProfile(PersonalRadar radar, {required bool initial})
      : fractions = List.unmodifiable([
          for (final axis in radar.axes)
            (initial ? axis.initialPercent : axis.currentPercent) == null
                ? null
                : (initial ? axis.initialPercent! : axis.currentPercent!)
                        .clamp(0, 100) /
                    100
        ]);
  final List<double?> fractions;
  bool get closed => fractions.length == 6 && fractions.every((v) => v != null);
}
