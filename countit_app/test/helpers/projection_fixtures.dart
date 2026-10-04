import 'package:countit_app/data/dtos/projection.dart';

/// `get_wallet_projection` answer from 2026-10-04 with a salary and rent,
/// or [flat] (no running rules: today's point only, horizon today + 30).
Map<String, dynamic> projectionJson({int walletId = 4, bool flat = false, String until = '2026-11-05'}) => {
  'wallet_id': walletId,
  'current_balance': 1250.5,
  'projected_balance': flat ? 1250.5 : 1750.5,
  'until': flat ? '2026-11-03' : until,
  'points': [
    {'date': '2026-10-04', 'income': 0, 'expense': 0, 'balance': 1250.5},
    if (!flat) ...[
      {'date': '2026-10-05', 'income': 0, 'expense': 400, 'balance': 850.5},
      {'date': '2026-10-31', 'income': 900, 'expense': 0, 'balance': 1750.5},
    ],
  ],
};

WalletProjection projectionFixture({bool flat = false, String until = '2026-11-05'}) =>
    WalletProjection.fromJson(projectionJson(flat: flat, until: until));
