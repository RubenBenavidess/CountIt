import 'package:flutter/material.dart';

import '../../../../data/dtos/budget.dart';

/// Material icon for each category of the API catalogue (card, selector).
extension BudgetIconData on BudgetIcon? {
  IconData get iconData => switch (this) {
    BudgetIcon.groceries => Icons.local_grocery_store_outlined,
    BudgetIcon.home => Icons.home_outlined,
    BudgetIcon.utilities => Icons.lightbulb_outline_rounded,
    BudgetIcon.transport => Icons.directions_bus_outlined,
    BudgetIcon.food => Icons.restaurant_outlined,
    BudgetIcon.health => Icons.local_hospital_outlined,
    BudgetIcon.education => Icons.school_outlined,
    BudgetIcon.entertainment => Icons.movie_outlined,
    BudgetIcon.clothing => Icons.checkroom_outlined,
    BudgetIcon.travel => Icons.flight_outlined,
    BudgetIcon.gifts => Icons.card_giftcard_outlined,
    BudgetIcon.pets => Icons.pets_outlined,
    BudgetIcon.phone => Icons.smartphone_outlined,
    BudgetIcon.savings => Icons.savings_outlined,
    BudgetIcon.salary => Icons.work_outline_rounded,
    BudgetIcon.business => Icons.storefront_outlined,
    BudgetIcon.debt => Icons.receipt_long_outlined,
    BudgetIcon.other => Icons.category_outlined,
    // A budget without category keeps the generic budget icon.
    null => Icons.pie_chart_outline_rounded,
  };
}
