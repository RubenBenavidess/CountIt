# Notificaciones push (F09 · HU-31)

La bandeja en la app ya funciona en vivo (Realtime sobre `public.notifications`). El **push** (FCM) está
preparado detrás de interfaces y apagado: la app usa `NoopPushMessaging` hasta que exista la configuración de
Firebase (COU-28 · COU-103). Este documento dice qué está listo y exactamente qué falta.

## Qué está listo

| Pieza | Dónde | Qué hace |
|---|---|---|
| `PushMessaging` (interfaz) + `NoopPushMessaging` | `lib/app/push/push_messaging.dart` | Costura con el proveedor: token, rotación, `deleteToken`, mensajes en primer plano, tocados y de arranque en frío. |
| `PushTokenService` | `lib/app/push/push_token_service.dart` | Tras el login `register_push_device(token, plataforma)` (COU-176); en cada rotación otra vez (COU-177); al cerrar sesión `unregister_push_device` **antes** de `auth.signOut()` y luego borra el token local (COU-178); con 401 solo borra el token local. Nunca registra tokens en logs; fallos y demoras (5 s) no bloquean al usuario. |
| `PushOpenHandler` | `lib/app/push/push_open_handler.dart` | Push tocado (segundo plano o arranque en frío) → `NotificationRoutes` → pantalla y marcado como leída (COU-199). En primer plano → recarga la bandeja y emite un `PushNotice` (COU-179). Sin sesión no hace nada; kinds desconocidos o ids inválidos abren la bandeja. |
| `PushNoticeHost` | `lib/presentation/notifications/view/push_notice_host.dart` | Snackbar con título, cuerpo y «Ver» para los push en primer plano. |
| `NotificationRoutes` | `lib/app/router/notification_routes.dart` | Enrutador puro por `kind` + `data` (strings de FCM incluidos), con validación estricta de ids (COU-180). |
| Permiso | `lib/shared/platform/notification_permission.dart` + `MainActivity.kt` (`ec.countit.app/notifications`) | `POST_NOTIFICATIONS` declarado; estado/solicitud/ajustes en Android 13+ (antes, el interruptor del sistema). Se pide desde la tarjeta de la bandeja (`PushPermissionCard`), **nunca al arrancar**, y solo si `PushMessaging.isAvailable` (COU-175). |
| Canal Android | `MainActivity.createNotificationChannel()` + `AndroidManifest.xml` | Canal `countit_default` «Count It!» (importancia alta) creado al iniciar; FCM lo usa por la meta-data `com.google.firebase.messaging.default_notification_channel_id` (COU-106). |
| Cableado | `lib/main.dart` | `SessionCubit(beforeSignOut: pushTokens.signingOut, onSessionLost: pushTokens.sessionLost)`, `pushTokens.setUser` sigue la sesión, `pushes.start()` tras restaurar la sesión (como los enlaces de Auth). |

Tests: `test/app/push/*`, `test/shared/platform/notification_permission_test.dart`,
`test/presentation/notifications/push_ui_test.dart`, `test/app/notification_routes_test.dart` (con
`FakePushMessaging`, `test/helpers/fake_push_messaging.dart`).

## Por qué no se agregaron `firebase_core`/`firebase_messaging` todavía

- Sin `google-services.json` el plugin de Gradle `com.google.gms.google-services` hace fallar el build, y sin él
  `Firebase.initializeApp()` falla en tiempo de ejecución (no hay `FirebaseOptions`). Inicializar condicionalmente
  dejaría código nativo y dependencias (minSdk, tamaño del APK) que no se pueden verificar.
- Toda la lógica que no depende de Firebase ya está y está probada: activar el push es implementar una clase y
  cambiar una línea de `main.dart`.

## Qué falta (en orden)

### 1. Proyecto de Firebase (COU-28, Ruben)
1. Crear el proyecto (recomendado: uno para `staging`+`local` y otro para `prod`, o uno solo con tres apps).
2. Registrar las apps Android con los ids de cada flavor: `ec.countit.app.local`, `ec.countit.app.staging`,
   `ec.countit.app`. Descargar cada `google-services.json` y dejarlo en:
   - `android/app/src/local/google-services.json`
   - `android/app/src/staging/google-services.json`
   - `android/app/src/prod/google-services.json`
   No son secretos (claves públicas restringidas por paquete), pero conviene **restringir la API key** en Google
   Cloud a las apps Android y a la API de FCM. Si se deciden versionar, el CI los necesita para compilar; si no,
   inyectarlos en CI desde secretos.
3. iOS (requiere la cuenta de Apple, COU-45): app `ec.countit.app` (y las de flavor cuando existan los
   *schemes*), `GoogleService-Info.plist` por configuración en `ios/Runner/` (o un script de *build phase* que
   copie el de cada configuración), clave **APNs `.p8`** subida a Firebase (Project settings → Cloud Messaging).
4. Backend: la cuenta de servicio de FCM ya está en los secretos de staging (`send-push`). Usar el **mismo
   proyecto** de Firebase que emite los tokens de la app.

### 2. Gradle (Android)
- `android/settings.gradle.kts` → `plugins { id("com.google.gms.google-services") version "<versión>" apply false }`.
- `android/app/build.gradle.kts` → `plugins { id("com.google.gms.google-services") }`.
- Comprobar `minSdk` que exija `firebase_messaging` (hoy `flutter.minSdkVersion`).

### 3. Paquetes (COU-103)
```bash
flutter pub add firebase_core firebase_messaging   # fijar versiones exactas y commitear pubspec.lock
```

### 4. Implementación de `PushMessaging` con FCM
Nuevo `lib/data/remote/firebase_push_messaging.dart`:
```dart
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._fcm);
  final FirebaseMessaging _fcm;

  @override bool get isAvailable => true;
  @override String? get platform => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android', TargetPlatform.iOS => 'ios', _ => null };
  @override Future<String?> getToken() => _fcm.getToken();          // iOS: requiere permiso + APNs
  @override Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;
  @override Future<void> deleteToken() => _fcm.deleteToken();
  @override Stream<PushMessage> get foregroundMessages => FirebaseMessaging.onMessage.map(_toMessage);
  @override Stream<PushMessage> get openedMessages => FirebaseMessaging.onMessageOpenedApp.map(_toMessage);
  @override Future<PushMessage?> initialMessage() async {
    final m = await _fcm.getInitialMessage();
    return m == null ? null : _toMessage(m);
  }
  static PushMessage _toMessage(RemoteMessage m) =>
      PushMessage(title: m.notification?.title, body: m.notification?.body, data: Map.unmodifiable(m.data));
}
```
En `main.dart`:
```dart
await Firebase.initializeApp();                       // tras WidgetsFlutterBinding.ensureInitialized()
await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: false);
final PushMessaging messaging = FirebasePushMessaging(FirebaseMessaging.instance);   // en lugar de NoopPushMessaging
```
- No hace falta `onBackgroundMessage`: el backend envía mensajes con `notification`, que el sistema muestra solo.
- **iOS:** el permiso lo pide `FirebaseMessaging.instance.requestPermission()`. Implementar
  `NotificationPermission` para iOS sobre esa llamada (o `getNotificationSettings()` para el estado) y elegirla
  en `main.dart` según la plataforma; Android sigue con `PlatformNotificationPermission`.
- Nunca registrar en logs el token ni `RemoteMessage` (usar `AppLogger` solo con claves).

### 5. iOS en Xcode (macOS)
- *Signing & Capabilities*: **Push Notifications** y **Background Modes → Remote notifications**
  (`aps-environment` en `Runner.entitlements`).
- `GoogleService-Info.plist` añadido al target Runner.

### 6. Verificación
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
