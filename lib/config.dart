/// Configuración de compilación.
///
/// `GITHUB_REPO` se puede sobreescribir al compilar:
/// `flutter build apk --release --dart-define=GITHUB_REPO=usuario/repo`.
/// Si queda vacío, la app no busca actualizaciones (no hay a dónde preguntar).
library;

const githubRepo = String.fromEnvironment('GITHUB_REPO', defaultValue: 'JuxnD/seguimiento');

bool get updatesConfigured => githubRepo.isNotEmpty && githubRepo.contains('/');

Uri get latestReleaseApi => Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest');

Uri get releasesPage => Uri.parse('https://github.com/$githubRepo/releases/latest');
