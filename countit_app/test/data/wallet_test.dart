import 'package:countit_app/data/dtos/bank.dart';
import 'package:countit_app/data/dtos/json_parsing.dart';
import 'package:countit_app/data/dtos/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `v_wallets` row as PostgREST returns it (contract 1.1).
const _row = <String, dynamic>{
  'wallet_id': 7,
  'owner_id': '6f0c1d7e-0000-0000-0000-000000000001',
  'owner_name': 'María Quishpe',
  'is_owner': true,
  'name': 'Ahorros',
  'description': 'Fondo de emergencia',
  'type': 'credit_card',
  'bank_id': 3,
  'bank_name': 'Banco Pichincha',
  'initial_balance': 1000.1,
  'total_income': 0.2,
  'total_expenses': 0.1,
  'balance': 1000.2,
  'created_at': '2026-10-01T15:00:00+00:00',
  'updated_at': '2026-10-02T15:00:00+00:00',
  'bank_color': '#F2C500',
  'member_count': 2,
  'month_income': 300,
  'month_expenses': '120.25',
  'projected_balance': 1180.95,
};

void main() {
  group('Wallet.fromJson', () {
    test('reads every column of v_wallets', () {
      final wallet = Wallet.fromJson(_row);
      expect(wallet.walletId, 7);
      expect(wallet.name, 'Ahorros');
      expect(wallet.isOwner, isTrue);
      expect(wallet.ownerName, 'María Quishpe');
      expect(wallet.description, 'Fondo de emergencia');
      expect(wallet.type, WalletType.creditCard);
      expect(wallet.bankId, 3);
      expect(wallet.bankName, 'Banco Pichincha');
      expect(wallet.bankColor, 0xFFF2C500);
      expect(wallet.memberCount, 2);
      expect(wallet.isShared, isTrue);
      expect(wallet.initialBalanceCents, 100010);
      expect(wallet.monthIncomeCents, 30000);
      expect(wallet.monthExpensesCents, 12025, reason: 'numeric may arrive as a string');
      expect(wallet.projectedBalanceCents, 118095);
      expect(wallet.hasProjection, isTrue);
      expect(wallet.createdAt, DateTime.utc(2026, 10, 1, 15));
    });

    test('amounts in cents have no floating point noise', () {
      final wallet = Wallet.fromJson(_row);
      // 0.1 + 0.2 != 0.3 in doubles; in cents it is exact.
      expect(wallet.totalIncomeCents + wallet.totalExpensesCents, 30);
      expect(wallet.balance, 1000.2);
    });

    test('tolerates the nullable columns (no bank, no colour, no projection, no type)', () {
      final wallet = Wallet.fromJson({
        'wallet_id': 8,
        'is_owner': false,
        'name': 'Casa',
        'type': null,
        'bank_id': null,
        'bank_name': null,
        'bank_color': null,
        'description': null,
        'initial_balance': 0,
        'total_income': 0,
        'total_expenses': 0,
        'balance': -12.5,
        'member_count': 1,
        'month_income': 0,
        'month_expenses': 0,
        'projected_balance': null,
      });
      expect(wallet.type, isNull);
      expect(wallet.bankId, isNull);
      expect(wallet.bankName, isNull);
      expect(wallet.bankColor, isNull);
      expect(wallet.projectedBalanceCents, isNull);
      expect(wallet.projectedBalance, isNull);
      expect(wallet.hasProjection, isFalse);
      expect(wallet.balanceCents, -1250);
      expect(wallet.isShared, isTrue, reason: 'someone shared it with the caller');
    });

    test('missing columns fall back to safe defaults', () {
      final wallet = Wallet.fromJson({'wallet_id': 9, 'is_owner': true});
      expect(wallet.name, '');
      expect(wallet.balanceCents, 0);
      expect(wallet.memberCount, 0);
      expect(wallet.isShared, isFalse);
    });
  });

  group('WalletType', () {
    test('maps 1:1 to the backend enum with Spanish labels', () {
      expect(WalletType.values.map((t) => t.apiValue), [
        'cash',
        'checking',
        'savings',
        'credit_card',
        'investment',
        'other',
      ]);
      expect(WalletType.values.map((t) => t.label), [
        'Efectivo',
        'Cuenta corriente',
        'Ahorros',
        'Tarjeta de crédito',
        'Inversión',
        'Otro',
      ]);
      for (final type in WalletType.values) {
        expect(WalletType.parse(type.apiValue), type);
      }
      expect(WalletType.parse('crypto'), isNull);
      expect(WalletType.parse(null), isNull);
    });
  });

  group('WalletInput.toParams', () {
    test('always sends every field, so update_wallet never clears data by omission', () {
      const input = WalletInput(name: '  Casa  ', type: WalletType.cash, description: '   ', initialBalanceCents: 1999);
      expect(input.toParams(), {
        'p_name': 'Casa',
        'p_bank_id': null,
        'p_description': null,
        'p_type': 'cash',
        'p_initial_balance': 19.99,
      });
    });

    test('fromWallet keeps bank, type and description', () {
      final params = WalletInput.fromWallet(Wallet.fromJson(_row)).toParams();
      expect(params['p_bank_id'], 3);
      expect(params['p_type'], 'credit_card');
      expect(params['p_description'], 'Fondo de emergencia');
      expect(params['p_initial_balance'], 1000.1);
    });
  });

  group('parsing helpers', () {
    test('hex colours', () {
      expect(parseHexColor('#0D1B2A'), 0xFF0D1B2A);
      expect(parseHexColor('e0e1dd'), 0xFFE0E1DD);
      expect(parseHexColor('#FFF'), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
      expect(parseHexColor(null), isNull);
    });

    test('cents', () {
      expect(Cents.parse(19.99), 1999);
      expect(Cents.parse('1234.50'), 123450);
      expect(Cents.parse('abc'), isNull);
      expect(Cents.parse(null), isNull);
      expect(Cents.fromAmount(0.29), 29);
    });

    test('Bank.fromJson reads v_banks with or without colour', () {
      final bank = Bank.fromJson({
        'bank_id': 1,
        'name': 'Banco Guayaquil',
        'country_code': 'EC',
        'is_active': true,
        'color': '#E6007E',
      });
      expect(bank, const Bank(bankId: 1, name: 'Banco Guayaquil', countryCode: 'EC', color: 0xFFE6007E));
      expect(Bank.fromJson({'bank_id': 2, 'name': 'JEP', 'color': null}).color, isNull);
    });
  });
}
