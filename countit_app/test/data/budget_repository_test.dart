import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/budget.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/repositories/budget_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockApiClient api;
  late SupabaseBudgetRepository budgets;

  setUp(() {
    api = MockApiClient();
    budgets = SupabaseBudgetRepository(api);
  });

  void selectReturns(List<Map<String, dynamic>> rows) => when(
    () => api.select(
      any(),
      columns: any(named: 'columns'),
      query: any(named: 'query'),
    ),
  ).thenAnswer((_) async => rows);

  Map<String, dynamic> row(int id, String name) => {
    'budget_id': id,
    'wallet_id': 4,
    'name': name,
    'limit_amount': 100,
    'start_date': '2026-10-01',
  };

  test('listByWallet reads v_budgets', () async {
    selectReturns([row(1, 'Comida'), row(2, 'Transporte')]);
    final result = await budgets.listByWallet(4);
    expect(result.map((b) => b.name), ['Comida', 'Transporte']);
    verify(() => api.select('v_budgets', query: any(named: 'query'))).called(1);
  });

  test('getById: no row is budget_not_found (404)', () async {
    selectReturns([]);
    await expectLater(
      budgets.getById(99),
      throwsA(
        isA<AppFailure>()
            .having((f) => f.kind, 'kind', FailureKind.notFound)
            .having((f) => f.key, 'key', 'budget_not_found')
            .having((f) => f.message, 'message', 'Presupuesto no encontrado'),
      ),
    );
  });

  test('getById returns the row', () async {
    selectReturns([row(7, 'Comida')]);
    expect((await budgets.getById(7)).budgetId, 7);
  });

  test('create sends create_budget with the wallet and every field, returns the id', () async {
    when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => {'budget_id': 12});
    final id = await budgets.create(4, BudgetInput(name: 'Comida', limitCents: 15000, startDate: DateTime(2026, 10)));
    expect(id, 12);
    verify(
      () => api.rpc<dynamic>(
        'create_budget',
        params: {
          'p_wallet_id': 4,
          'p_name': 'Comida',
          'p_limit_amount': 150.0,
          'p_start_date': '2026-10-01',
          'p_period': 'monthly',
          'p_end_date': null,
          'p_type': 'expense',
          'p_icon': null,
        },
      ),
    ).called(1);
  });

  test('update sends update_budget with the full state', () async {
    when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => {});
    await budgets.update(
      5,
      BudgetInput(
        name: 'Viaje',
        limitCents: 50000,
        startDate: DateTime(2026, 10),
        period: BudgetPeriod.none,
        endDate: DateTime(2026, 12, 31),
        icon: BudgetIcon.travel,
      ),
    );
    verify(
      () => api.rpc<dynamic>(
        'update_budget',
        params: {
          'p_budget_id': 5,
          'p_name': 'Viaje',
          'p_limit_amount': 500.0,
          'p_start_date': '2026-10-01',
          'p_period': 'none',
          'p_end_date': '2026-12-31',
          'p_type': 'expense',
          'p_icon': 'travel',
        },
      ),
    ).called(1);
  });

  test('delete passes the reauth prompt to delete_budget', () async {
    when(
      () => api.rpc<dynamic>(
        any(),
        params: any(named: 'params'),
        onReauth: any(named: 'onReauth'),
      ),
    ).thenAnswer((_) async => {});
    Future<bool> prompt() async => true;
    final ReauthPrompt onReauth = prompt;
    await budgets.delete(5, onReauth: onReauth);
    final captured = verify(
      () => api.rpc<dynamic>(
        'delete_budget',
        params: {'p_budget_id': 5},
        onReauth: captureAny(named: 'onReauth'),
      ),
    ).captured;
    expect(captured.single, same(onReauth));
  });
}
