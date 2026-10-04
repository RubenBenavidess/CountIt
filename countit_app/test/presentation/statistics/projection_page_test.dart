import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/app/session/session_cubit.dart';
import 'package:countit_app/app/session/session_state.dart';
import 'package:countit_app/data/dtos/profile.dart';
import 'package:countit_app/data/dtos/projection.dart';
import 'package:countit_app/presentation/statistics/view/projection_page.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/date_picker.dart';
import '../../helpers/mocks.dart';
import '../../helpers/projection_fixtures.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

Profile _profile({required bool projection}) => Profile(
  userId: 'u1',
  username: 'anap',
  email: 'ana@correo.ec',
  role: UserRole.user,
  timezone: 'America/Guayaquil',
  plan: UserPlan(
    planId: projection ? 3 : 2,
    name: projection ? 'Contador Profesional' : 'Contador',
    limits: {PlanFeatures.walletProjection: projection ? 1 : 0},
  ),
);

void main() {
  late MockAnalysisRepository analysis;

  setUpAll(Dates.init);

  setUp(() => analysis = MockAnalysisRepository());

  Future<void> pumpPage(WidgetTester tester, {bool projection = true}) async {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = MockAuthRepository();
    when(() => auth.sessionChanges).thenAnswer((_) => const Stream.empty());
    final session = SessionCubit(auth: auth, profiles: MockProfileRepository())
      ..emit(SessionState.authenticated(_profile(projection: projection)));
    addTearDown(session.close);
    await tester.pumpApp(
      ProjectionPage(wallet: walletFixture(id: 4, name: 'Pichincha')),
      auth: auth,
      session: session,
      analysis: analysis,
    );
  }

  group('ProjectionPage (COU-99)', () {
    testWidgets('loading, then summary, stepped chart and upcoming movements', (tester) async {
      final pending = Completer<WalletProjection>();
      when(() => analysis.walletProjection(4)).thenAnswer((_) => pending.future);
      await pumpPage(tester);
      expect(find.bySemanticsLabel('Cargando proyección'), findsOneWidget);
      pending.complete(projectionFixture());
      await tester.pumpAndSettle();
      expect(find.text(r'$1.250,50'), findsOneWidget);
      expect(find.text('Saldo al 5 nov 2026'), findsOneWidget);
      expect(find.text(r'+ $500,00'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Gráfico de saldo proyectado hasta el 5 nov 2026\. Hoy \$1\.250,50')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'Punto más bajo: \$850,50 el 5 oct 2026')), findsOneWidget);
      expect(find.bySemanticsLabel('5 oct 2026: − \$400,00. Saldo después: \$850,50'), findsOneWidget);
      expect(find.bySemanticsLabel('31 oct 2026: + \$900,00. Saldo después: \$1.750,50'), findsOneWidget);
    });

    testWidgets('no running rules: the balance stays, said in words', (tester) async {
      when(() => analysis.walletProjection(4)).thenAnswer((_) async => projectionFixture(flat: true));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('No hay movimientos programados activos hasta el 3 nov 2026'), findsOneWidget);
    });

    testWidgets('error with retry', (tester) async {
      var calls = 0;
      when(() => analysis.walletProjection(4)).thenAnswer((_) async {
        if (calls++ == 0) throw _network;
        return projectionFixture();
      });
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Próximos movimientos'), findsOneWidget);
    });

    testWidgets('a chosen date asks the API for it; «Volver a automático» drops it', (tester) async {
      final today = Dates.userToday('America/Guayaquil');
      final chosen = DateTime(today.year, today.month, today.day + 60);
      when(() => analysis.walletProjection(4)).thenAnswer((_) async => projectionFixture());
      when(() => analysis.walletProjection(4, until: chosen))
          .thenAnswer((_) async => projectionFixture(until: Dates.toApi(chosen)));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Proyectar hasta: Automático')), findsOneWidget);
      await pickDate(tester, 'Proyectar hasta', chosen);
      verify(() => analysis.walletProjection(4, until: chosen)).called(1);
      expect(find.text('Saldo al ${Dates.date(chosen)}'), findsOneWidget);
      await tester.tap(find.text('Volver a automático'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Proyectar hasta: Automático')), findsOneWidget);
      expect(find.text('Saldo al 5 nov 2026'), findsOneWidget);
      verify(() => analysis.walletProjection(4)).called(1);
    });
  });

  group('gating (COU-172)', () {
    testWidgets('Contador: locked screen without asking the API, «Ver planes»', (tester) async {
      await pumpPage(tester, projection: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('projection-locked')), findsOneWidget);
      verifyNever(() => analysis.walletProjection(any(), until: any(named: 'until')));
      await tester.tap(find.text('Ver planes'));
      await tester.pumpAndSettle();
      expect(find.text(projectionNotInPlanTitle), findsOneWidget);
    });

    testWidgets('a 403 from the API locks it too', (tester) async {
      when(() => analysis.walletProjection(4))
          .thenThrow(const AppFailure(kind: FailureKind.featureNotInPlan, message: 'Tu plan no incluye…', status: 403));
      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('projection-locked')), findsOneWidget);
    });
  });
}
