# Purpose:
reusable building blocks used by multiple features, including design system, generic widgets, utilities, extensions, mixins, and animations.

## Use it for: 
cross-feature components, empty/error/loading views, formatters/validators/result utilities, and ergonomic extensions.

## Key practices: 
promote components only when reused by more than one feature, consume tokens instead of hardcoded values, and offer a standardized Result type.

## Objective structure: 
design_system, widgets, utils, extensions, mixins, and animations that remain feature-agnostic.

## Key practices
- Promote a widget to Shared only when used by >1 feature.
- Components consume tokens, not hardcoded values.
- Provide a Result type to standardize success/error flows across the app.

## Objective structure
/shared
|
├── design_system/
│   ├── tokens.dart               // spacing, radius, breakpoints, colors
│   └── components/
│       ├── app_button.dart
│       ├── app_text_field.dart
│       └── app_card.dart
├── widgets/
│   ├── empty_state.dart
│   ├── error_view.dart
│   └── loading_indicator.dart
├── utils/
│   ├── formatters.dart           // currency/date
│   ├── validators.dart           // email/password rules
│   ├── result.dart               // Result<T>/Failure helpers
│   └── debounce.dart
├── extensions/
│   ├── context_ext.dart          // context.theme, context.l10n, etc.
│   └── string_ext.dart
├── mixins/
│   └── paginable.dart            // para la paginacion de distintos dtos
└── animations/
    └── animations.dart