import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/repositories/plan_repository.dart';
import 'package:countit_app/presentation/plans/cubit/plan_catalog_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';
import '../helpers/plan_fixtures.dart';

void main() {
  late MockApiClient api;
  late SupabasePlanRepository plans;
  const offline = AppFailure(kind: FailureKind.network, message: 'Sin conexión');

  setUp(() {
    api = MockApiClient();
    plans = SupabasePlanRepository(api);
  });

  void selectAnswers(Future<List<Map<String, dynamic>>> Function() answer) => when(
    () => api.select(
      any(),
      columns: any(named: 'columns'),
      query: any(named: 'query'),
    ),
  ).thenAnswer((_) => answer());

  int selects() => verify(() => api.select('v_plans', query: any(named: 'query'))).callCount;

  test('reads v_plans: id, name, description, price in cents and limits', () async {
    selectAnswers(() async => planRowsJson);
    final offers = await plans.list();
    expect(offers.map((o) => o.planId), [1, 2, 3]);
    final pro = offerById(offers, 3)!;
    expect(pro.name, 'Contador Profesional');
    expect(pro.description, 'Gestión ilimitada con vistas analíticas.');
    expect(pro.plan.monthlyPriceCents, 499);
    expect(pro.plan.quota('max_scheduled_transactions'), 50);
    expect(offerById(offers, 1)!.plan.isPaid, isFalse);
    expect(offerById(offers, 9), isNull);
  });

  test('cached in memory: a second list does not call the API; refresh does', () async {
    selectAnswers(() async => planRowsJson);
    await plans.list();
    await plans.list();
    expect(selects(), 1);
    await plans.list(refresh: true);
    expect(selects(), 1);
  });

  test('concurrent first loads share one request', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    selectAnswers(() => pending.future);
    final first = plans.list();
    final second = plans.list();
    pending.complete(planRowsJson);
    expect(await first, await second);
    expect(selects(), 1);
  });

  test('a failed refresh falls back to the cached catalogue', () async {
    selectAnswers(() async => planRowsJson);
    final cached = await plans.list();
    selectAnswers(() async => throw offline);
    expect(await plans.list(refresh: true), cached);
  });

  test('without a cached catalogue the failure propagates, and the next call retries', () async {
    selectAnswers(() async => throw offline);
    await expectLater(plans.list(), throwsA(offline));
    selectAnswers(() async => planRowsJson);
    expect(await plans.list(), hasLength(3));
  });

  test('a missing description is empty', () async {
    selectAnswers(
      () async => [
        {'plan_id': 4, 'name': 'Beta', 'description': null, 'monthly_price': 1, 'limits': <String, dynamic>{}},
      ],
    );
    expect((await plans.list()).single.description, isEmpty);
  });
}
