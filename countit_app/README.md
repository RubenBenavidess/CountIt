# Count It! — app móvil (Flutter)

App Android/iOS de finanzas personales con billeteras compartidas. El backend vive en
[CountIt-Backend-Dev](https://github.com/RubenBenavidess/CountIt-Backend-Dev) (Supabase); su contrato está en `docs/API.md`
y `docs/api-schema.json` de ese repositorio. Diseño: lienzo *CountIt App* (tokens en `lib/app/theme/tokens.dart`).

## Requisitos
- Flutter **3.47.6** (stable) · Dart 3.13 · Java 17 para Android.
- Id de paquete: `ec.countit.app` (Android e iOS).

## Ejecutar
Cada entorno es un *flavor* con su propio id, nombre e ícono, así pueden convivir instaladas (COU-40):

| Flavor | Android id | Nombre | Ícono | Config |
|---|---|---|---|---|
| `local` | `ec.countit.app.local` | Count It! Local | insignia «L» | `env/local.json` (versionado) |
| `staging` | `ec.countit.app.staging` | Count It! Staging | insignia «S» | `env/staging.json` (copiar de `staging.example.json`; ignorado por git) |
| `prod` | `ec.countit.app` | Count It! | logo | `env/prod.json` (ignorado por git) |

**Ícono** (COU-55): adaptativo (fondo `#0D1B2A`, logo dentro de la zona segura de 66/108 dp), monocromo para los
íconos temáticos de Android 13+, mipmaps *legacy* por densidad e `AppIcon` de iOS sin transparencia. Todos salen de
`scripts/generate_brand_icons.py` (Pillow), que redibuja el logo con Manrope porque el original (101×131 px) no da
para 432 px ni 1024 px; los flavors `local`/`staging` sobrescriben el *foreground* en `android/app/src/<flavor>/res`.

**iOS:** hoy hay un único target (`ec.countit.app`, «Count It!»). Los flavors de iOS requieren Xcode (macOS) y se
dejan para cuando exista la cuenta de Apple (COU-45): crear las configuraciones `Debug-<flavor>`/`Release-<flavor>`/
`Profile-<flavor>` y un *scheme* compartido por flavor (mismo nombre que el flavor de Android), y en cada configuración
`PRODUCT_BUNDLE_IDENTIFIER` = `ec.countit.app[.local|.staging]` y una variable `APP_DISPLAY_NAME` usada por
`CFBundleDisplayName` en `Info.plist`. Verificar con `flutter build ios --no-codesign --flavor staging`.

```bash
flutter pub get
# Backend local (supabase start en el repo del backend). 10.0.2.2 = el host visto desde el emulador de Android;
# en un teléfono físico, copia env/local.json y usa la IP de tu PC en la red.
flutter run --flavor local --dart-define-from-file=env/local.json
flutter run --flavor staging --dart-define-from-file=env/staging.json
```
La configuración solo lleva valores públicos: URL y *anon key* de Supabase y, cuando se active el captcha (COU-25),
`TURNSTILE_SITE_KEY` + `TURNSTILE_BASE_URL` (https de un hostname permitido en el sitio de Turnstile; la página del
widget se carga bajo ese origen). Sin site key los formularios no muestran captcha. Nada secreto va en la app.

**Dependencias:** `pubspec.yaml` declara rangos (`^`) y `pubspec.lock` (versionado) fija las versiones exactas; el CI
instala con `flutter pub get --enforce-lockfile` y falla si no coinciden. Actualiza a propósito (`flutter pub upgrade`
o los PRs semanales de Dependabot, que también cubren las GitHub Actions, fijadas por SHA) y sube el lock en el mismo PR.

**Enlaces de los correos** (`countit://auth/confirmed`, `countit://auth/reset-password`): el backend los usa si tiene
`AUTH_EMAIL_REDIRECT_URL` y `PASSWORD_RESET_REDIRECT_URL` (ver su README) y la URL está en *Redirect URLs* de Auth.
Probar en un emulador: `adb shell am start -W -a android.intent.action.VIEW -d "countit://auth/confirmed" ec.countit.app.local`.

## Calidad
```bash
dart format lib test          # ancho 120 (analysis_options.yaml)
flutter analyze
flutter test
```
Test de contrato **en vivo** contra un backend levantado (local o staging), con una cuenta demo
(`scripts/seed-demo.sh` del backend). Se salta si no recibe las variables y no corre en CI:
```bash
flutter test test/live --dart-define=LIVE_API_URL=http://127.0.0.1:54321 --dart-define=LIVE_ANON_KEY=<anon> \
  --dart-define=LIVE_EMAIL=demo_ana@smoke.test --dart-define=LIVE_PASSWORD=<DEMO_PASSWORD>
```

Release (ofuscado): `scripts/build_release.sh <staging|prod> [appbundle|apk|ipa]`.

CI (`.github/workflows/flutter.yml`): formato, análisis, tests y build de APK debug en cada PR.

## Seguridad

| Control | Dónde |
|---|---|
| Sesión cifrada en Keystore/Keychain, nunca en preferencias | `lib/data/remote/secure_session_storage.dart` |
| Sin secretos en la app (solo URL y *anon key*, públicas); `env/staging.json` y `env/prod.json` fuera de git | `env/`, `.gitignore` |
| HTTPS obligatorio; HTTP solo en el flavor `local` y solo hacia 10.0.2.2/localhost; sin CAs instaladas por el usuario | `AppConfig`, `android/app/src/{main,local}/res/xml/network_security_config.xml` |
| Sin respaldos en la nube ni copia a otro dispositivo | `AndroidManifest.xml` (`allowBackup=false`, `data_extraction_rules.xml`) |
| Errores sin textos internos (5xx → mensaje genérico) | `ErrorMapper` |
| 401 cierra la sesión; una contraseña incorrecta **no** | `ErrorMapper`, `ApiClient`, `SessionCubit` |
| Acciones destructivas con confirmación de contraseña y un solo reintento | `ApiClient.run(onReauth:)` |
| Logs solo en debug y con tokens, contraseñas y correos ocultos | `lib/app/logging/app_logger.dart` |
| Capturas y grabación bloqueadas en pantallas sensibles (`SecureScreen`); contenido oculto en el selector de apps (`PrivacyCurtain`) | `lib/shared/widgets/secure_screen.dart` |
| Builds de release ofuscados con símbolos aparte | `scripts/build_release.sh` |
| Captcha Turnstile en webview: site key validada, navegación limitada al origen del reto, token de un solo uso | `lib/shared/widgets/turnstile_field.dart` |
| El enlace de confirmación no inicia sesión (el login pasa por la Edge Function); el de recuperación solo abre «nueva contraseña» | `lib/app/links/auth_links.dart`, `redirectFor` |
| Contraseñas sin autocorrección ni sugerencias del teclado; mensajes de login y recuperación que no revelan si el correo existe | `AppTextField`, pantallas de `presentation/auth` |
| 429: el botón se bloquea con cuenta regresiva según `Retry-After` | `ApiClient.invoke`, `CooldownButton` |
| Cerrar sesión y eliminar la cuenta limpian primero el estado y luego el SDK borra los tokens locales, aunque falle la red | `SessionCubit.signOut` |
| Acciones destructivas: hoja «Confirma que eres tú» (contraseña, 3 intentos / 2 min, cuenta bloqueada) | `presentation/account/view/reauth_sheet.dart` |
| Exportación LOPDP en la caché privada; la anterior se borra al generar una nueva | `lib/shared/platform/file_sharer.dart` |

Pendiente (Linear, Q2 · Seguridad móvil): App Links/Universal Links verificados en lugar de solo `countit://`
(requiere dominio, COU-109), detección informativa de root/jailbreak (COU-116), firma de release (COU-58),
revisión OWASP MASVS (COU-119) y bloqueo de capturas en iOS.

## Arquitectura
Capas `app/` (composición: config, tema, router, errores, sesión), `data/` (clientes y repositorios),
`presentation/` (features con View + Cubit) y `shared/` (componentes reutilizables). Estado con **flutter_bloc**.
Cada carpeta tiene su README con reglas.

- **Backend:** `ApiClient` (`lib/data/remote`) es la única puerta: RPC y vistas del esquema `api`, Edge Functions con
  `x-device-id` (cliente HTTP propio para leer `Retry-After`), y todo error convertido en `AppFailure` (mensaje en español + clave estable del backend, `lib/app/errors`).
  Un 401 avisa a `SessionCubit`, que cierra la sesión y lleva al login. Las acciones destructivas pasan `onReauth`:
  ante `403 reauth_required` se pide la contraseña y se reintenta una vez.
- **Sesión:** el login va por la Edge Function `login` y la sesión se entrega al SDK con `setSession`; se guarda en el
  almacenamiento seguro del sistema (`SecureSessionStorage`). `SessionCubit` tiene un estado `passwordRecovery` para el
  enlace de recuperación; `AuthLinkHandler` (`lib/app/links`) traduce los enlaces de los correos en navegación.
- **Formularios:** `SubmitCubit` (`lib/shared/state`) es la plantilla de todo formulario que envía una petición
  (estado de carga, error con mensajes por campo, cuenta regresiva del 429, doble toque ignorado); `Validators`
  replica las reglas del backend y `FormScreenBody` fija la acción principal abajo sin romper el teclado.
- **Componentes** (`lib/shared/widgets`): `AppButton`, campos (`AppTextField`, `AppPasswordField`, `AppMoneyField`
  con máximo 2 decimales, `AppDateField`, `AppDropdownField`), `AppCard`, `AppBadge`, `AppProgressBar`,
  `showConfirmDialog` (devuelve `bool`), `showAppBottomSheet`, `EmptyState`/`LoadingView`/`ErrorView`,
  `LoadStateView` para el `LoadState<T>` de los Cubits y `showAppSnackBar` (no se apilan), `AppBanner`, `AppTopBar`,
  `AppLink`, `CooldownButton`, `PasswordChecklist`, `IconTile` y `CaptchaSlot`/`TurnstileField`.
- **Formato** (`lib/shared/utils`): `Money` (`$1.234,56`, estilo ecuatoriano acordado en COU-18; signo `+`/`−` en movimientos) y `Dates`
  (español, «Hoy»/«Ayer», y el «hoy» en la zona horaria del perfil, con America/Guayaquil por defecto).
- **Navegación:** `go_router` con redirecciones por sesión y rol (`lib/app/router`).
- **Cuenta:** perfil con plan y acciones, datos personales (con zona horaria IANA), cambiar contraseña, exportar datos
  y eliminar cuenta. Para borrar algo: `api.rpc(..., onReauth: reauthPrompt(context, action: 'eliminar «Hogar»',
  confirmLabel: 'Eliminar billetera'))`.

## Rendimiento (reglas del árbol de widgets)
- `const` en todo widget sin estado variable (lo exige el análisis).
- Leer del estado lo mínimo: `context.select((SessionCubit c) => c.state.profile)` en vez de `watch` del Cubit
  entero; `BlocConsumer` con `listenWhen`/`buildWhen` para efectos (navegar, limpiar un campo, snackbars).
- Lo que cambia seguido se reconstruye solo: la cuenta regresiva (`CooldownButton`), el checklist de contraseña
  (`ValueListenableBuilder` sobre el controller), el botón «Guardar» con cambios, la fila «Exportar» mientras carga.
- Listas largas con `ListView.builder` (y `itemExtent` si la altura es fija); los formularios cortos se construyen
  completos para que `validate()` revise todos los campos.
- Diseño en una sola pasada: `SliverFillRemaining` en vez de `IntrinsicHeight` para fijar botones abajo.
- Sin trabajo pesado en `build`: formatos (`NumberFormat`, regex) se crean una vez como `static final`.
