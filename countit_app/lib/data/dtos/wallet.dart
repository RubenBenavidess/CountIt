import 'package:equatable/equatable.dart';

import 'json_parsing.dart';

/// `public.wallet_type` (API: Billeteras · tipos), with its Spanish label.
enum WalletType {
  cash('cash', 'Efectivo'),
  checking('checking', 'Cuenta corriente'),
  savings('savings', 'Ahorros'),
  creditCard('credit_card', 'Tarjeta de crédito'),
  investment('investment', 'Inversión'),
  other('other', 'Otro');

  const WalletType(this.apiValue, this.label);

  /// Value sent to and received from the API (`p_type`, `v_wallets.type`).
  final String apiValue;

  /// Spanish name shown to the user.
  final String label;

  /// Null for a missing or unknown value (the type is optional in the API).
  static WalletType? parse(Object? value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }
}

/// A row of `api.v_wallets` (HU-08): own and shared wallets with bank, owner,
/// totals and this month's movements.
///
/// Amounts are kept in cents ([Cents]) so sums and comparisons never show
/// floating point noise; the `double` getters are for display only.
class Wallet extends Equatable {
  const Wallet({
    required this.walletId,
    required this.name,
    required this.isOwner,
    this.ownerId,
    this.ownerName,
    this.description,
    this.type,
    this.bankId,
    this.bankName,
    this.bankColor,
    this.memberCount = 0,
    this.initialBalanceCents = 0,
    this.totalIncomeCents = 0,
    this.totalExpensesCents = 0,
    this.balanceCents = 0,
    this.monthIncomeCents = 0,
    this.monthExpensesCents = 0,
    this.projectedBalanceCents,
    this.createdAt,
    this.updatedAt,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
    walletId: (json['wallet_id'] as num).toInt(),
    name: (json['name'] as String?) ?? '',
    isOwner: json['is_owner'] == true,
    ownerId: json['owner_id'] as String?,
    ownerName: json['owner_name'] as String?,
    description: json['description'] as String?,
    type: WalletType.parse(json['type']),
    bankId: (json['bank_id'] as num?)?.toInt(),
    bankName: json['bank_name'] as String?,
    bankColor: parseHexColor(json['bank_color']),
    memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    initialBalanceCents: Cents.parse(json['initial_balance']) ?? 0,
    totalIncomeCents: Cents.parse(json['total_income']) ?? 0,
    totalExpensesCents: Cents.parse(json['total_expenses']) ?? 0,
    balanceCents: Cents.parse(json['balance']) ?? 0,
    monthIncomeCents: Cents.parse(json['month_income']) ?? 0,
    monthExpensesCents: Cents.parse(json['month_expenses']) ?? 0,
    projectedBalanceCents: Cents.parse(json['projected_balance']),
    createdAt: parseTimestamp(json['created_at']),
    updatedAt: parseTimestamp(json['updated_at']),
  );

  final int walletId;
  final String name;

  /// True for the caller's own wallets; false for wallets shared with them.
  final bool isOwner;
  final String? ownerId;
  final String? ownerName;
  final String? description;

  /// Optional in the API: null when the wallet has no type.
  final WalletType? type;
  final int? bankId;
  final String? bankName;

  /// Bank colour as opaque ARGB (`#RRGGBB` → `0xFFRRGGBB`); null = default colour.
  final int? bankColor;

  /// Accepted members besides the owner.
  final int memberCount;
  final int initialBalanceCents;
  final int totalIncomeCents;
  final int totalExpensesCents;
  final int balanceCents;
  final int monthIncomeCents;
  final int monthExpensesCents;

  /// Balance projected to the end of the month: only with the plan feature
  /// `wallet_projection` (Contador Profesional); null otherwise.
  final int? projectedBalanceCents;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Shared with someone (owner side) or by someone (member side).
  bool get isShared => !isOwner || memberCount > 0;

  bool get hasProjection => projectedBalanceCents != null;

  double get balance => Cents.toAmount(balanceCents);
  double get initialBalance => Cents.toAmount(initialBalanceCents);
  double get totalIncome => Cents.toAmount(totalIncomeCents);
  double get totalExpenses => Cents.toAmount(totalExpensesCents);
  double get monthIncome => Cents.toAmount(monthIncomeCents);
  double get monthExpenses => Cents.toAmount(monthExpensesCents);
  double? get projectedBalance => projectedBalanceCents == null ? null : Cents.toAmount(projectedBalanceCents!);

  @override
  List<Object?> get props => [
    walletId,
    name,
    isOwner,
    ownerId,
    ownerName,
    description,
    type,
    bankId,
    bankName,
    bankColor,
    memberCount,
    initialBalanceCents,
    totalIncomeCents,
    totalExpensesCents,
    balanceCents,
    monthIncomeCents,
    monthExpensesCents,
    projectedBalanceCents,
    createdAt,
    updatedAt,
  ];
}

/// What the wallet form sends to `create_wallet` / `update_wallet`.
///
/// `update_wallet` replaces the wallet: an omitted bank, description or type
/// is cleared, so [toParams] always sends every field (COU-194).
class WalletInput extends Equatable {
  const WalletInput({required this.name, this.type, this.bankId, this.description, this.initialBalanceCents = 0});

  /// The form's current state for an existing wallet (edit mode).
  factory WalletInput.fromWallet(Wallet wallet) => WalletInput(
    name: wallet.name,
    type: wallet.type,
    bankId: wallet.bankId,
    description: wallet.description,
    initialBalanceCents: wallet.initialBalanceCents,
  );

  final String name;
  final WalletType? type;
  final int? bankId;
  final String? description;
  final int initialBalanceCents;

  Map<String, dynamic> toParams() {
    final description = this.description?.trim();
    return {
      'p_name': name.trim(),
      'p_bank_id': bankId,
      'p_description': description == null || description.isEmpty ? null : description,
      'p_type': type?.apiValue,
      'p_initial_balance': Cents.toAmount(initialBalanceCents),
    };
  }

  @override
  List<Object?> get props => [name, type, bankId, description, initialBalanceCents];
}
