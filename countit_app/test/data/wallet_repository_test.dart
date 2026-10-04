import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/repositories/bank_repository.dart';
import 'package:countit_app/data/repositories/wallet_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockApiClient api;
  late SupabaseWalletRepository wallets;

  setUp(() {
    api = MockApiClient();
    wallets = SupabaseWalletRepository(api);
  });

  void selectReturns(List<Map<String, dynamic>> rows) => when(
    () => api.select(
      any(),
      columns: any(named: 'columns'),
      query: any(named: 'query'),
    ),
  ).thenAnswer((_) async => rows);

  test('list reads v_wallets', () async {
    selectReturns([
      {'wallet_id': 1, 'name': 'Ahorros', 'is_owner': true},
      {'wallet_id': 2, 'name': 'Casa', 'is_owner': false},
    ]);
    final result = await wallets.list();
    expect(result.map((w) => w.name), ['Ahorros', 'Casa']);
    verify(() => api.select('v_wallets', query: any(named: 'query'))).called(1);
  });

  test('getById: no row is wallet_not_found (404)', () async {
    selectReturns([]);
    await expectLater(
      wallets.getById(99),
      throwsA(
        isA<AppFailure>()
            .having((f) => f.kind, 'kind', FailureKind.notFound)
            .having((f) => f.key, 'key', 'wallet_not_found')
            .having((f) => f.message, 'message', 'Billetera no encontrada'),
      ),
    );
  });

  test('create sends create_wallet with every field and returns the id', () async {
    when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => {'wallet_id': 12});
    final id = await wallets.create(const WalletInput(name: 'Casa', type: WalletType.cash, bankId: 3));
    expect(id, 12);
    verify(
      () => api.rpc<dynamic>(
        'create_wallet',
        params: {'p_name': 'Casa', 'p_bank_id': 3, 'p_description': null, 'p_type': 'cash', 'p_initial_balance': 0.0},
      ),
    ).called(1);
  });

  test('update sends update_wallet with the full state', () async {
    when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => {});
    await wallets.update(
      5,
      const WalletInput(
        name: 'Casa',
        type: WalletType.savings,
        bankId: 1,
        description: 'Gastos',
        initialBalanceCents: 5000,
      ),
    );
    verify(
      () => api.rpc<dynamic>(
        'update_wallet',
        params: {
          'p_wallet_id': 5,
          'p_name': 'Casa',
          'p_bank_id': 1,
          'p_description': 'Gastos',
          'p_type': 'savings',
          'p_initial_balance': 50.0,
        },
      ),
    ).called(1);
  });

  test('delete passes the reauth prompt to delete_wallet', () async {
    when(
      () => api.rpc<dynamic>(
        any(),
        params: any(named: 'params'),
        onReauth: any(named: 'onReauth'),
      ),
    ).thenAnswer((_) async => {});
    Future<bool> prompt() async => true;
    final ReauthPrompt onReauth = prompt;
    await wallets.delete(5, onReauth: onReauth);
    final captured = verify(
      () => api.rpc<dynamic>(
        'delete_wallet',
        params: {'p_wallet_id': 5},
        onReauth: captureAny(named: 'onReauth'),
      ),
    ).captured;
    expect(captured.single, same(onReauth));
  });

  group('banks', () {
    test('list reads v_banks and keeps the active ones', () async {
      selectReturns([
        {'bank_id': 1, 'name': 'Banco Guayaquil', 'is_active': true, 'color': '#E6007E'},
        {'bank_id': 2, 'name': 'Banco Viejo', 'is_active': false},
      ]);
      final banks = await SupabaseBankRepository(api).list(search: 'ban');
      expect(banks.map((b) => b.name), ['Banco Guayaquil']);
      verify(() => api.select('v_banks', query: any(named: 'query'))).called(1);
    });

    test('search pattern drops PostgREST syntax', () {
      expect(SupabaseBankRepository.pattern('pichincha'), '%pichincha%');
      expect(SupabaseBankRepository.pattern('a,b(c)%_*'), '%a b c%');
    });
  });
}
