# CLAUDE.md — CountIt (app Flutter)

App móvil de **Count It!** (finanzas personales con billeteras compartidas, Ecuador, USD) en `countit_app/`. El backend
es Supabase en [CountIt-Backend-Dev](https://github.com/RubenBenavidess/CountIt-Backend-Dev); su contrato
(`docs/API.md`, hoy **1.3**, y `docs/api-schema.json`) manda: la app no inventa reglas que el backend no tenga.
UI en **español (es-EC)**; código, identificadores, comentarios y nombres de tests en **inglés**.

Guía práctica para trabajar sin asistente (emulador, cuentas demo, comandos, CI, despliegue): Linear → documento *Desarrollo local y pruebas (guía sin Claude)*.

Referencias: `countit_app/README.md` (ejecución, flavors, release, tabla de seguridad), `countit_app/docs/`
(`SECURITY.md`, `RELEASE.md`, `PUSH.md`), `countit_app/test/README.md`, Linear *CountIt!* → proyecto
*App móvil (Flutter)* (milestones F01–F11) y *Calidad y seguridad* (Q1–Q3).

## Comandos (desde `countit_app/`)
```bash
flutter pub get --enforce-lockfile        # el lock es obligatorio (CI falla si no coincide)
dart format lib test                      # ancho 120
flutter analyze                           # sin issues
flutter test                              # toda la suite en verde (~780 tests)
flutter run --flavor staging --dart-define-from-file=env/staging.json
scripts/build_release.sh <staging|prod> [apk|appbundle]   # ofuscado + R8; símbolos aparte
```
Flutter 3.47.6 · Dart 3.13 · Java 17 (`JAVA_HOME` del JBR de Android Studio). Tras un `flutter build`,
`(cd android && ./gradlew --stop)` para liberar memoria.

## Arquitectura y capas
- `lib/app/`: composición y políticas transversales: `config/` (`AppConfig` desde `--dart-define`), `theme/`
  (tokens del lienzo *CountIt App*), `router/` (go_router, guardas de sesión y rol, `NotificationRoutes`),
  `errors/` (`ErrorMapper`: hint del backend → `AppFailure` con mensaje en español), `session/` (`SessionCubit`,
  `SessionSecureScreen`), `links/`, `push/`, `plans/` (gating), `logging/` (`AppLogger`).
- `lib/data/`: `remote/` (`ApiClient` sobre supabase-flutter con esquema `api`, Edge Functions, Realtime, almacén
  seguro), `dtos/` (parseo defensivo, montos en centavos), `repositories/` (interfaz + `Supabase…Repository`).
- `lib/presentation/<feature>/{cubit,view}`: una carpeta por feature (auth, account, home, wallets, budgets,
  transactions, scheduled, families, statistics, notifications, plans, profile, admin, shell, splash). Cubits con
  estados `Equatable`; la vista solo lee estado y llama al cubit.
- `lib/shared/`: widgets del diseño (`AppTextField`, `AppMoneyField`, `LoadStateView`, `SecureScreen`…), `state/`
  (`LoadState`), `utils/` (`Dates`, `Money`, validadores con los límites del contrato), `platform/`.
- Inyección: repositorios con `RepositoryProvider` en `main.dart`; las pantallas los leen con `context.read`.
  Algo va a `shared/` solo cuando tiene **3 o más usos reales**.

## Convenciones
- Toda llamada pasa por `ApiClient.run`/`select`/`rpc`/`invoke`: errores → `AppFailure`, 401 cierra la sesión,
  403 `feature_not_in_plan` abre la hoja de planes, 403 `reauth_required` pide contraseña y reintenta una vez.
- Montos: `int` en centavos en la app, `Money.format` para mostrar (`$1.234,56`), `Cents.toAmount` para la API.
  Fechas del usuario con `Dates` (zona del perfil); `await Dates.init()` antes de formatear.
- Pantallas grandes: `BlocSelector`/`context.select`/`buildWhen`, listas con `.builder`, nada pesado en `build`.
- Tests espejo de `lib/` (`test/<ruta>/<archivo>_test.dart`); `tester.pumpApp(...)` con mocks (mocktail) o fakes;
  flujos completos con `buildRouter` real y backend en memoria (`*_flow_test.dart`, COU-164/COU-245). Sin red en
  los tests normales; `test/live/` es opcional y se salta sin `--dart-define`.

## Seguridad (detalle en `countit_app/docs/SECURITY.md`)
- Sesión solo en Keystore/Keychain; la primera ejecución de una instalación borra el almacén seguro previo.
- Nada de `print`/`debugPrint`: `AppLogger` (solo debug, redactado). Nunca loguear tokens, montos, correos ni nombres.
- `FLAG_SECURE` en toda la app con sesión (`SessionSecureScreen`) y en pantallas de contraseñas; `PrivacyCurtain`.
- Enlaces de Auth solo como App Links verificados `https://countit-bft.pages.dev/auth/{confirmed,reset-password}`
  (`AUTH_LINK_HOST`, `authLinkHost` en Gradle, `site/.well-known/assetlinks.json`); sin esquema propio. `data` de
  notificaciones validado en `NotificationRoutes`.
- `env/*.json` solo con valores públicos (URL, *anon key*, site key de Turnstile). `env/staging.json`/`prod.json`,
  `android/key.properties` y keystores **nunca** al repo.

## Flujo de trabajo
- Rama por cambio desde `main` (`feat/…`, `fix/…`, `chore/…`, `docs/…`), PRs pequeños y no apilados.
- Antes de subir: format + analyze + test en verde y, si toca UI, verificación en el emulador contra staging.
- Commits en español. PR con `gh pr create -R RubenBenavidess/CountIt --base main` y cuerpo en español
  (**Spec, Context, What Changed, How to test**); CI (`flutter.yml`: formato, análisis, tests y APK debug) en verde
  → `gh pr merge <n> --squash --delete-branch`. Correcciones con commits nuevos; sin force-push.
- Al cerrar trabajo de Linear, comentar la evidencia en el issue (si Linear no está disponible, anotar en
  `~/CountIt/linear-updates.md` para sincronizar después).
- Invitar a la familia va por la Edge Function `invite-member` (contrato 1.3), no por el RPC.

## Gotchas
- **Emulador en Wayland:** lanzarlo con `-feature -GuestAngle` (`emulator -avd CountIt_Pixel_8 -no-boot-anim
  -feature -GuestAngle`) o la pantalla no se dibuja bien. Puede caerse durante un build de Gradle pesado: volver a
  levantarlo.
- **Capturas negras:** con sesión iniciada `FLAG_SECURE` está activo; `adb exec-out screencap` sale negro. Para
  revisar la UI usar `uiautomator dump` (textos y etiquetas semánticas) o las pantallas sin sesión.
- **Rate limits de staging:** login 5 contraseñas incorrectas por dispositivo cada 30 min (los inicios correctos no
  cuentan; capa por IP de 60 intentos cada 15 min), reautenticación 3 cada 2 min, invitar 30 intentos al día por usuario.
  Cuentas demo `delivered+demo_<ana|carlos|lucia>@resend.dev` (contraseña en la guía de Linear); no modificar sus
  datos de forma permanente.
- Instalar un build nuevo encima de uno viejo sin la marca de instalación pide login otra vez (`FreshInstall`).
  Un APK firmado con otra clave (release vs debug) exige desinstalar antes.
- `pubspec.lock` versionado y `--enforce-lockfile`: una dependencia nueva va con su lock en el mismo PR.
- `/tmp` es tmpfs con cuota de usuario (~6 GB): `build/app` ocupa ~2 GB; bórralo si `flutter test` falla con
  «Disk quota exceeded».
- Release: el aviso «ELF library contains unobfuscated DWARF» de `--split-debug-info` no afecta al APK (los
  `libapp.so` empaquetados no llevan secciones `.debug`); los símbolos quedan en `build/symbols/…`.
- iOS: un solo target sin flavors hasta tener cuenta de Apple (COU-45); `FLAG_SECURE` no existe (COU-115).

## Estado (04/10/2026)
F01–F10 implementados en `main` (base, auth y cuenta, billeteras, presupuestos, movimientos, programadas, familias,
estadísticas y proyección, bandeja en vivo, planes y administración); navegación inferior Inicio · Movimientos ·
Estadísticas · Perfil, animaciones (respetan «reducir movimiento») y monto grande coloreado al registrar movimientos.
Push FCM activo en `staging` con `android/app/src/staging/google-services.json` local (no versionado, `docs/PUSH.md`);
falta Firebase para `local`/`prod` e iOS. Pendiente de cuentas externas: **captcha** COU-25, Universal Links de iOS (COU-132), flavors iOS (Xcode) y **F11** publicación (Play Console, Apple Developer, keystore COU-58).

