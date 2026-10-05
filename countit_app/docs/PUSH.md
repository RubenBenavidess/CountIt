# Notificaciones push (F09 · HU-31)

La bandeja en la app funciona en vivo (Realtime sobre `public.notifications`) y el **push** (FCM) está activo
en los flavors que tienen su `google-services.json` (hoy: `staging`). Sin ese archivo la app usa
`NoopPushMessaging` y todo lo demás sigue igual (COU-28 · COU-103).

## Archivos de Firebase por flavor (no se versionan)

| Flavor | Paquete | Archivo |
|---|---|---|
| `local` | `ec.countit.app.local` | `android/app/src/local/google-services.json` |
| `staging` | `ec.countit.app.staging` | `android/app/src/staging/google-services.json` (proyecto `countit-6e32f`) |
| `prod` | `ec.countit.app` | `android/app/src/prod/google-services.json` |

- Están en `.gitignore` (`android/app/src/*/google-services.json`); el dueño los guarda fuera del repo y los copia
  al clonar. Comprobar que `client[].client_info.android_client_info.package_name` coincide con el flavor.
- Gradle (`android/app/build.gradle.kts`) aplica `com.google.gms.google-services` **solo si algún flavor tiene
  su archivo**, con `missingGoogleServicesStrategy = IGNORE`: el CI (flavor `local`, sin archivos) y los flavors
  sin Firebase compilan igual.
- En tiempo de ejecución `initPushMessaging()` (`lib/data/remote/firebase_push_messaging.dart`) intenta
  `Firebase.initializeApp()` (5 s máx.); si falla (sin archivo, plataforma no soportada) usa el no-op y solo
  registra el tipo de error. Nunca se registran tokens ni mensajes.

## Qué está listo

| Pieza | Dónde | Qué hace |
|---|---|---|
| `PushMessaging` (interfaz) + `NoopPushMessaging` | `lib/app/push/push_messaging.dart` | Costura con el proveedor: token, rotación, `deleteToken`, mensajes en primer plano, tocados y de arranque en frío. |
| `FirebasePushMessaging` + `initPushMessaging()` | `lib/data/remote/firebase_push_messaging.dart` | Implementación con `firebase_messaging`; `main.dart` la usa solo si Firebase arranca, si no `NoopPushMessaging`. |
| `PushTokenService` | `lib/app/push/push_token_service.dart` | Tras el login `register_push_device(token, plataforma)` (COU-176); en cada rotación otra vez (COU-177); al cerrar sesión `unregister_push_device` **antes** de `auth.signOut()` y luego borra el token local (COU-178); con 401 solo borra el token local. Nunca registra tokens en logs; fallos y demoras (5 s) no bloquean al usuario. |
| `PushOpenHandler` | `lib/app/push/push_open_handler.dart` | Push tocado (segundo plano o arranque en frío) → `NotificationRoutes` → pantalla y marcado como leída (COU-199). En primer plano → recarga la bandeja y emite un `PushNotice` (COU-179). Sin sesión no hace nada; kinds desconocidos o ids inválidos abren la bandeja. |
| `PushNoticeHost` | `lib/presentation/notifications/view/push_notice_host.dart` | Snackbar con título, cuerpo y «Ver» para los push en primer plano. |
| `NotificationRoutes` | `lib/app/router/notification_routes.dart` | Enrutador puro por `kind` + `data` (strings de FCM incluidos), con validación estricta de ids (COU-180). |
| Permiso | `lib/shared/platform/notification_permission.dart` + `MainActivity.kt` (`ec.countit.app/notifications`) | `POST_NOTIFICATIONS` declarado; estado/solicitud/ajustes en Android 13+ (antes, el interruptor del sistema). Se pide desde la tarjeta de la bandeja (`PushPermissionCard`), **nunca al arrancar**, y solo si `PushMessaging.isAvailable` (COU-175). |
| Canal Android | `MainActivity.createNotificationChannel()` + `AndroidManifest.xml` | Canal `countit_default` «Count It!» (importancia alta) creado al iniciar; FCM lo usa por la meta-data `com.google.firebase.messaging.default_notification_channel_id` (COU-106). |
| Cableado | `lib/main.dart` | `final messaging = await initPushMessaging()`, `SessionCubit(beforeSignOut: pushTokens.signingOut, onSessionLost: pushTokens.sessionLost)`, `pushTokens.setUser` sigue la sesión, `pushes.start()` tras restaurar la sesión (como los enlaces de Auth). |

Tests: `test/app/push/*`, `test/shared/platform/notification_permission_test.dart`,
`test/presentation/notifications/push_ui_test.dart`, `test/app/notification_routes_test.dart` (con
`FakePushMessaging`, `test/helpers/fake_push_messaging.dart`).

## Qué falta

### 1. Firebase para `local` y `prod` (Ruben)
Registrar en Firebase las apps `ec.countit.app.local` y `ec.countit.app` (prod, idealmente en un proyecto
propio) y dejar cada `google-services.json` en su carpeta (tabla de arriba). No son secretos (claves públicas
restringidas por paquete), pero conviene **restringir la API key** en Google Cloud a las apps Android y a FCM. El
backend (`send-push`) debe usar la cuenta de servicio del **mismo proyecto** que emite los tokens.

### 2. iOS (requiere la cuenta de Apple, COU-45; macOS)
- App `ec.countit.app` en Firebase, `GoogleService-Info.plist` en `ios/Runner/` (ignorado en git) y clave
  **APNs `.p8`** subida a Firebase (Project settings → Cloud Messaging).
- Xcode, *Signing & Capabilities*: **Push Notifications** y **Background Modes → Remote notifications**.
- El permiso lo pide `FirebaseMessaging.instance.requestPermission()`: implementar `NotificationPermission`
  para iOS sobre esa llamada (`getNotificationSettings()` para el estado) y elegirla en `main.dart` por
  plataforma; Android sigue con `PlatformNotificationPermission`.
- No hace falta `onBackgroundMessage`: el backend envía mensajes con `notification`, que el sistema muestra solo.

### 3. Verificación
Hecha en staging (Android 16, emulador con Google Play, 04/10/2026): 1 (dispositivo registrado tras el login y
el permiso aceptado desde la bandeja), 2 (`push_status = sent`, llegó al canal `countit_default`; al tocarla
abrió la app en la bandeja y la marcó leída). Pendientes de repetir en un teléfono real: 3–6.

1. Login en un dispositivo → `push_devices` tiene el token con la plataforma correcta.
2. Generar una notificación (presupuesto al 80 %, invitación) con la app en segundo plano → llega al canal
   «Count It!»; tocarla abre la billetera/invitaciones y la marca leída.
3. Con la app abierta → snackbar con «Ver», sin notificación del sistema duplicada.
4. App cerrada → tocar el push abre la pantalla tras el splash.
5. Cerrar sesión → el token desaparece de `push_devices`; un push posterior no llega.
6. Iniciar sesión con otra cuenta en el mismo teléfono → el token pasa a esa cuenta (auditado en el backend).

## Notas del contrato
- `send-push` no envía `android.notification.channel_id`: el canal sale de la meta-data del manifiesto. Si se
  agrega en el backend, usar `countit_default`.
- En el push todos los valores de `data` son strings (`notification_id`, `wallet_id`…); `NotificationRoutes` ya
  los acepta y valida.
