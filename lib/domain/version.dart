/// Comparación de versiones semánticas (`1.2.3`), tolerante a `v1.2.3`,
/// a sufijos de build (`1.2.3+7`) y a versiones con menos partes (`1.2`).
library;

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  /// Devuelve null si el texto no parece una versión.
  static AppVersion? tryParse(String raw) {
    final t = raw.trim().replaceFirst(RegExp('^[vV]'), '').split('+').first.split('-').first;
    final parts = t.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final nums = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null || n < 0) return null;
      nums.add(n);
    }
    return AppVersion(nums[0], nums.length > 1 ? nums[1] : 0, nums.length > 2 ? nums[2] : 0);
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion o) {
    if (major != o.major) return major.compareTo(o.major);
    if (minor != o.minor) return minor.compareTo(o.minor);
    return patch.compareTo(o.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}

/// true si `candidate` es más nueva que `current`. Ante un texto que no se
/// puede leer, devuelve false: nunca se anuncia una actualización dudosa.
bool isNewerVersion(String candidate, String current) {
  final a = AppVersion.tryParse(candidate);
  final b = AppVersion.tryParse(current);
  if (a == null || b == null) return false;
  return a.compareTo(b) > 0;
}
