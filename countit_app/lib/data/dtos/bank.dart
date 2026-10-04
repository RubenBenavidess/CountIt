import 'package:equatable/equatable.dart';

import 'json_parsing.dart';

/// A row of `api.v_banks` (HU-27): the active catalogue users pick from.
class Bank extends Equatable {
  const Bank({required this.bankId, required this.name, this.countryCode, this.isActive = true, this.color});

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
    bankId: (json['bank_id'] as num).toInt(),
    name: (json['name'] as String?) ?? '',
    countryCode: json['country_code'] as String?,
    isActive: json['is_active'] != false,
    color: parseHexColor(json['color']),
  );

  final int bankId;
  final String name;
  final String? countryCode;
  final bool isActive;

  /// Brand colour as opaque ARGB; null = default wallet colour.
  final int? color;

  @override
  List<Object?> get props => [bankId, name, countryCode, isActive, color];
}

/// What an admin sends to create or edit a bank (`admin_create_bank`,
/// `admin_update_bank` · HU-27).
class BankInput extends Equatable {
  const BankInput({required this.name, required this.countryCode, this.color});

  final String name;

  /// ISO 3166-1 alpha-2, uppercase (`EC`).
  final String countryCode;

  /// Opaque ARGB; null = no colour (wallets use the default).
  final int? color;

  @override
  List<Object?> get props => [name, countryCode, color];
}
