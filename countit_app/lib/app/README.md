# Purpose:
app-wide orchestration for bootstrap, routing, theming, DI, configuration, error mapping, logging, and session.

## Contains:
config/, theme/ and (as F01 advances) router/, errors/, session/ as the single source of composition and policies.

## Avoid:
feature-specific UI or transport details; keep it to composition and cross-cutting concerns.

## Key practices:
features depend on repository interfaces provided with `RepositoryProvider` (flutter_bloc) at the root; configuration comes from `--dart-define-from-file=env/<env>.json`.

## Objective structure
/app
├── app.dart                  // MaterialApp: theme, es-EC locale, router
├── config/
│   └── app_config.dart       // local/staging/prod from dart-defines (public values only)
├── theme/
│   ├── tokens.dart           // colours, spacing, radii, sizes, type scale (design canvas)
│   └── app_theme.dart        // ThemeData dark (default) / light + AppPalette extension
├── router/                   // go_router, auth/role guards, deep links
├── errors/                   // backend hint → AppFailure → Spanish message
└── session/                  // SessionCubit (session restore, sign-out, 401 handling)
