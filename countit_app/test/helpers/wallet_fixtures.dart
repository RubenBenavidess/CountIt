import 'package:countit_app/data/dtos/bank.dart';
import 'package:countit_app/data/dtos/wallet.dart';

/// Wallet as `v_wallets` would return it; amounts in dollars for readability.
Wallet walletFixture({
  int id = 1,
  String name = 'Ahorros',
  bool isOwner = true,
  WalletType? type = WalletType.savings,
  int? bankId = 3,
  String? bankName = 'Banco Pichincha',
  int? bankColor = 0xFFF2C500,
  String? description,
  int memberCount = 0,
  double balance = 1250.5,
  double initialBalance = 1000,
  double totalIncome = 400,
  double totalExpenses = 149.5,
  double monthIncome = 300,
  double monthExpenses = 120.25,
  double? projectedBalance,
  String? ownerName = 'María Quishpe',
}) => Wallet(
  walletId: id,
  name: name,
  isOwner: isOwner,
  ownerId: isOwner ? 'u1' : 'u2',
  ownerName: ownerName,
  type: type,
  bankId: bankId,
  bankName: bankName,
  bankColor: bankColor,
  description: description,
  memberCount: memberCount,
  balanceCents: (balance * 100).round(),
  initialBalanceCents: (initialBalance * 100).round(),
  totalIncomeCents: (totalIncome * 100).round(),
  totalExpensesCents: (totalExpenses * 100).round(),
  monthIncomeCents: (monthIncome * 100).round(),
  monthExpensesCents: (monthExpenses * 100).round(),
  projectedBalanceCents: projectedBalance == null ? null : (projectedBalance * 100).round(),
);

const banksFixture = [
  Bank(bankId: 1, name: 'Banco Guayaquil', color: 0xFFE6007E),
  Bank(bankId: 3, name: 'Banco Pichincha', color: 0xFFF2C500),
  Bank(bankId: 9, name: 'Cooperativa JEP'),
];
