# Purpose:
UI layer organized by feature, with Views and Cubits (flutter_bloc) that turn app state into widgets and user interactions into actions, strictly separating concerns.

## Use it for:
screens, feature widgets, and state exposure through Cubits that consume repositories via interfaces.

## Contains:
feature folders, each with /view and /cubit; immutable states (equatable), and simple UI validation.

## Avoid:
direct API calls, JSON parsing, transport details, or business logic inside widgets; keep widgets "dumb".

## Key practices:
one main page per feature, one Cubit per page, explicit loading/success/failure states, deterministic side effects.

## Testing:
widget tests for views and unit tests for Cubits (bloc_test) with mocked repositories.

## Objective structure:
/presentation
└── <feature>/
    ├── view/
    │   ├── <feature>_page.dart
    │   └── widgets/
    └── cubit/
        ├── <feature>_state.dart
        └── <feature>_cubit.dart
