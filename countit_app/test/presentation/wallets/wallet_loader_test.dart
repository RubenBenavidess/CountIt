import 'package:countit_app/data/repositories/wallet_repository.dart';
import 'package:countit_app/presentation/wallets/view/wallet_loader.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/wallet_fixtures.dart';

void main() {
  late MockWalletRepository wallets;

  setUpAll(Dates.init);
  setUp(() => wallets = MockWalletRepository());

  Widget loader() =>
      WalletLoader(walletId: 2, title: 'Programados', builder: (wallet) => Text('rules of ${wallet.name}'));

  testWidgets('opened from a notification: loads the wallet, then builds the screen', (tester) async {
    when(() => wallets.getById(2)).thenAnswer((_) async => walletFixture(id: 2, name: 'Efectivo'));
    await tester.pumpApp(loader(), wallets: wallets);
    await tester.pumpAndSettle();
    expect(find.text('rules of Efectivo'), findsOneWidget);
  });

  testWidgets('a wallet that is not mine (or gone) never builds the screen', (tester) async {
    when(() => wallets.getById(2)).thenThrow(SupabaseWalletRepository.notFound);
    await tester.pumpApp(loader(), wallets: wallets);
    await tester.pumpAndSettle();
    expect(find.textContaining('rules of'), findsNothing);
    expect(find.text('Billetera no encontrada'), findsOneWidget);
  });
}
