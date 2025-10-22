# Purpose: 
UI layer organized by feature, with Views and ViewModels that transform app state into widgets and user interactions into actions, strictly separating concerns

## Use it for: 
screens, feature widgets, and state exposure through ViewModels that consume repositories/services via interfaces.​

## Contains: 
feature folders, each with /view and /viewmodel; immutable state models, actions, and simple UI validation.

## Avoid: 
direct API calls, JSON parsing, transport details, or business logic inside widgets; keep widgets “dumb.”

## Key practices: 
one main view per feature, one ViewModel per view, explicit loading/success/error states, and deterministic side-effects.

## Testing: 
widget tests for views and unit tests for ViewModels with mocked repositories/services.

## Objective structure:
feature folders with view and viewmodel subfolders and clear naming like wallet_page.dart and wallet_viewmodel.dart.    ​

/presentation
└── <feature>/
    ├── view/
    │   ├── <feature>_page.dart
    │   └── widgets/
    │       └── <feature>_part.dart
    └── viewmodel/
        ├── <feature>_state.dart
        └── <feature>_viewmodel.dart
