# Purpose:
expose immutable UI state and actions, orchestrating repository/service calls and mapping failures to UI-ready states.

## Contains:
<feature>_state.dart for state models and <feature>_viewmodel.dart for async actions, simple validation, and state transitions.

## Avoid:
transport concerns, JSON/DTO handling, or direct widget manipulation.

## Key practices:
idempotent methods, explicit state enums/flags, and dependency injection via interfaces.

## Testing:
unit tests with mocked repositories/services to validate transitions and error paths.

## Naming:
<feature>_viewmodel.dart with clear verb-based methods like load(), refresh(), submit().