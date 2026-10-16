import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/features/settings/updates_card.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/test_fonts.dart';

const _noNewer = 'No hay una actualización más nueva disponible.';
const _oldConclusion = 'Estás en la última versión publicada.';
const _api = 'https://api.github.com/repos/qa/ficticio/releases/latest';
const _apk = 'https://github.com/qa/ficticio/releases/download/v1.21.0/qa.apk';

http.Response releaseResponse({int status = 200}) => http.Response(
    jsonEncode({
      'tag_name': 'v1.21.0',
      'html_url': 'https://github.com/qa/ficticio/releases/tag/v1.21.0',
      'body': '',
      'assets': [
        {'name': 'qa.apk', 'browser_download_url': _apk}
      ],
    }),
    status);

Future<void> renderCard(WidgetTester tester,
    {required String installed,
    required http.Client client,
    double textScale = 1}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await loadTestFonts(tester);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        appVersionProvider.overrideWith((_) => installed),
        updateServiceProvider.overrideWith((ref) {
          final service =
              UpdateService(client: client, apiUrl: Uri.parse(_api));
          ref.onDispose(service.close);
          return service;
        }),
      ],
      child: MaterialApp(
          theme: buildGymTheme(),
          home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: const Scaffold(
                  body: SingleChildScrollView(child: UpdatesCard()))))));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('seguimiento/sistema');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final nativeCalls = <MethodCall>[];
  setUp(() {
    nativeCalls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('1.22 instalada sobre pública1.21 no acredita publicación',
      (tester) async {
    await renderCard(tester, installed: '1.22.0',
        client: MockClient((request) async {
      expect(request.url.toString(), _api);
      return releaseResponse();
    }));
    expect(find.text('Versión instalada: 1.22.0'), findsOneWidget);
    expect(find.text(_noNewer), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '));
    expect(find.text(_oldConclusion), findsNothing);
    expect(find.text('Descargar APK'), findsNothing);
    expect(nativeCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    for (final installed in ['1.21.0', '1.22.0']) {
      testWidgets('sin nueva instalada$installed 360 texto$scale',
          (tester) async {
        await renderCard(tester,
            installed: installed,
            textScale: scale,
            client: MockClient((_) async => releaseResponse()));
        expect(find.text('Versión instalada: $installed'), findsOneWidget);
        expect(find.text(_noNewer), findsOneWidget);
        expect(find.text(_oldConclusion), findsNothing);
        expect(tester.takeException(), isNull);
        expect(nativeCalls, isEmpty);
      });
    }
    testWidgets('publicada nueva conserva URL y espera toque texto$scale',
        (tester) async {
      await renderCard(tester,
          installed: '1.20.0',
          textScale: scale,
          client: MockClient((_) async => releaseResponse()));
      expect(find.text('Hay una versión nueva: v1.21.0'), findsOneWidget);
      expect(find.text(_noNewer), findsNothing);
      expect(nativeCalls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Descargar APK'));
      await tester.pumpAndSettle();
      expect(nativeCalls, hasLength(1));
      expect(nativeCalls.single.method, 'openApkDownload');
      expect(nativeCalls.single.arguments, {'url': _apk});
      expect(tester.takeException(), isNull);
    });
  }

  for (final status in [404, 503]) {
    testWidgets('error$status conserva el motivo sin afirmar publicación',
        (tester) async {
      await renderCard(tester,
          installed: '1.22.0',
          client: MockClient((_) async => releaseResponse(status: status)));
      expect(
          find.text(status == 404
              ? 'Todavía no hay ninguna versión publicada.'
              : 'GitHub respondió 503.'),
          findsOneWidget);
      expect(find.text(_noNewer), findsNothing);
      expect(find.text(_oldConclusion), findsNothing);
      expect(nativeCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('058: con manifiesto, «Actualizar» pide el permiso de instalar una vez',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      return call.method == 'canInstallPackages' ? false : true;
    });
    await renderCard(tester, installed: '1.20.0', client: MockClient((_) async {
      return http.Response(
          jsonEncode({
            'tag_name': 'v1.21.0',
            'html_url': 'https://github.com/qa/ficticio/releases/tag/v1.21.0',
            'body': '',
            'assets': [
              {'name': 'qa.apk', 'browser_download_url': _apk},
              {
                'name': 'qa.manifest.json',
                'browser_download_url':
                    'https://github.com/qa/ficticio/releases/download/v1.21.0/qa.manifest.json'
              },
            ],
          }),
          200);
    }));
    expect(find.byKey(const ValueKey('actualizar')), findsOneWidget);
    expect(find.text('Descargar con el navegador'), findsOneWidget);
    expect(find.text('Descargar APK'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('actualizar')));
    await tester.pumpAndSettle();
    expect(find.text('Permite instalar la actualización'), findsOneWidget);
    await tester.tap(find.text('Abrir el ajuste'));
    await tester.pumpAndSettle();
    expect([for (final c in nativeCalls) c.method],
        ['canInstallPackages', 'openInstallPermission']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('058: sin manifiesto queda la descarga por el navegador', (tester) async {
    await renderCard(tester,
        installed: '1.20.0', client: MockClient((_) async => releaseResponse()));
    expect(find.byKey(const ValueKey('actualizar')), findsNothing);
    expect(find.text('Descargar APK'), findsOneWidget);
  });
}
