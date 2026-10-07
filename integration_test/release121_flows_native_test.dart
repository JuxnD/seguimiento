import 'package:integration_test/integration_test.dart';

import '../test/ui/release121_flows_test.dart' as flows;

/// Mismos oráculos de usuario, en el runtime Android y SQLite nativo.
/// Sólo datos ficticios/in-memory; no abre gateway ni historial del owner.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  flows.main();
}
