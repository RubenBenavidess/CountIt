# Purpose: 
app-wide orchestration for bootstrap, routing, theming, DI, configuration, error mapping, analytics, logging, and session.

## Contains: 
bootstrap/, router/, theme/, di/, config/, errors/, analytics/, logging/, and session/ as the single source of composition and policies.

## Avoid: 
feature-specific UI or transport details; keep it to composition and cross-cutting concerns.

## Key practices: 
features depend on interfaces and are registered in DI here, with environment-driven configuration.

## Objective structure
/app
|
├── bootstrap/
│   └── bootstrap.dart        // error handling, env load, runZonedGuarded
├── router/
│   ├── app_router.dart       // routes, deep links
│   └── guards.dart           // auth/onboarding guards
├── theme/
│   ├── tokens.dart           // spacing, colors, typography scale
│   └── app_theme.dart        // ThemeData(light/dark)
├── di/
│   └── di.dart               // get_it
├── config/
│   └── app_config.dart       // dev/stg/prod, feature flags
├── errors/
│   └── error_mapper.dart     // Exception → AppFailure → UI message
├── logging/
│   └── logger.dart           // Shared logger for all the app
└── session/
    └── session_controller.dartS