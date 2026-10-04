# Tests de la app

`test/` es espejo de `lib/`: el test de `lib/<ruta>/<archivo>.dart` va en `test/<ruta>/<archivo>_test.dart`.

| Tipo | Dónde | Herramientas |
|---|---|---|
| Unidad (formateadores, modelos, mapeo de errores, `ApiClient`) | `test/<capa>/…_test.dart` | `flutter_test`, `mocktail` |
| Cubits | `test/app/…`, `test/presentation/<feature>/cubit/…` | `bloc_test` con repositorios mockeados |
| Widgets y pantallas | `test/shared/widgets/…`, `test/presentation/<feature>/view/…` | `tester.pumpApp(...)` |
| Contrato en vivo (opcional) | `test/live/` | Backend local o staging; se salta sin `--dart-define` (ver README de la app) |
| Flujos con router real y backend en memoria (COU-164 registro → login → logout, COU-245 billetera → movimiento) | `test/presentation/<feature>/…_flow_test.dart` | `pumpApp(router: buildRouter(...))` con repositorios falsos en memoria |
| Integración en dispositivo (más adelante, Q3 · COU-120) | `integration_test/` | `integration_test` |

## Utilidades (`test/helpers`)
- `pumpApp(widget, {auth, profiles, wallets, banks, budgets, transactions, scheduled, families, notifications, notificationsCubit, pushMessaging, notificationPermission, analysis, admin, plans, session, router, config, themeMode})`: monta el widget con el tema del diseño, locale
  es-EC y los `RepositoryProvider`/`BlocProvider` de la raíz. Por defecto usa mocks; pasa los tuyos para controlar
  respuestas. Con `router` monta la app completa para probar navegación.
- `mocks.dart`: `MockAuthRepository`, `MockProfileRepository`, `MockWalletRepository`, `MockBankRepository`, `MockBudgetRepository`, `MockTransactionRepository`, `MockScheduledTransactionRepository`, `MockAnalysisRepository`, `MockFamilyRepository` (`noFamilies()` en `pump_app.dart`: sin miembros ni invitaciones), `MockNotificationRepository` (`noNotifications()`: bandeja vacía), `MockPushDeviceRepository`, `MockNotificationPermission`; `FakePushMessaging` (`fake_push_messaging.dart`) controla tokens, rotaciones y mensajes push, `MockApiClient`, `MockSecureStorage` (mocktail); `FakePlanRepository` y `planOffers` (`plan_fixtures.dart`, catálogo `v_plans` por defecto en `pumpApp`).

## Convenciones
- Nombres de test en inglés, describiendo el comportamiento: `'reauth cancelled: nothing is retried'`.
- Un `group` por unidad; los casos de error con la clave del backend que prueban (`'… invalid_amount'`).
- Los formateadores de fechas necesitan `await Dates.init()` en `setUpAll`.
- Sin red en los tests normales: todo backend se sustituye por mocks.
