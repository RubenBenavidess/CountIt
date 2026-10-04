import 'package:equatable/equatable.dart';

import '../../shared/utils/dates.dart';
import 'json_parsing.dart';

/// One day of the projection: what the running scheduled rules register
/// that day and the balance after them. The first point is today (no
/// movements, the current balance).
class ProjectionPoint extends Equatable {
  const ProjectionPoint({
    required this.date,
    required this.incomeCents,
    required this.expenseCents,
    required this.balanceCents,
  });

  factory ProjectionPoint.fromJson(Map<String, dynamic> json) => ProjectionPoint(
    date: Dates.parseDay(json['date'] as String),
    incomeCents: Cents.parse(json['income']) ?? 0,
    expenseCents: Cents.parse(json['expense']) ?? 0,
    balanceCents: Cents.parse(json['balance']) ?? 0,
  );

  final DateTime date;
  final int incomeCents;
  final int expenseCents;
  final int balanceCents;

  /// True when a scheduled rule moves money that day.
  bool get hasMovements => incomeCents != 0 || expenseCents != 0;

  @override
  List<Object?> get props => [date, incomeCents, expenseCents, balanceCents];
}

/// Result of `api.get_wallet_projection` (HU-25 · COU-24): the balance of a
/// readable wallet day by day from its running scheduled rules (active, not
/// paused, of authors still in the wallet) until [until].
class WalletProjection extends Equatable {
  WalletProjection({
    required this.walletId,
    required this.currentBalanceCents,
    required this.projectedBalanceCents,
    required this.until,
    required this.points,
  }) : movements = List.unmodifiable(points.where((point) => point.hasMovements));

  factory WalletProjection.fromJson(Map<String, dynamic> json) {
    final points = [
      if (json['points'] is List)
        for (final row in json['points'] as List) ProjectionPoint.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    final current = Cents.parse(json['current_balance']) ?? 0;
    return WalletProjection(
      walletId: (json['wallet_id'] as num).toInt(),
      currentBalanceCents: current,
      projectedBalanceCents: Cents.parse(json['projected_balance']) ?? current,
      until: Dates.parseDay(json['until'] as String),
      points: List.unmodifiable(points),
    );
  }

  final int walletId;
  final int currentBalanceCents;

  /// Balance after the last projected day.
  final int projectedBalanceCents;

  /// Last day projected: the chosen date, the last occurrence of the rules
  /// (at most a year ahead) or today + 30 without rules.
  final DateTime until;

  /// Today first, then one point per day with movements, oldest first.
  final List<ProjectionPoint> points;

  int get changeCents => projectedBalanceCents - currentBalanceCents;

  /// The days with scheduled movements (today's starting point excluded),
  /// derived once per answer.
  final List<ProjectionPoint> movements;

  /// No running rule moves money before [until].
  bool get isFlat => movements.isEmpty;

  @override
  List<Object?> get props => [walletId, currentBalanceCents, projectedBalanceCents, until, points];
}
