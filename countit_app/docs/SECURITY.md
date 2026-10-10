# Seguridad de la app (OWASP MASVS-L1)

Revisión pragmática de `lib/`, `android/` e `ios/` (Q2 · COU-119). El backend aplica la autorización (RLS, RPC con
chequeos, cupos, modo seguro); la app no guarda secretos ni decide permisos, solo evita filtrar lo que muestra.

## Controles aplicados

| MASVS | Control | Dónde |
|---|---|---|
| STORAGE-1 | Sesión de Supabase solo en Keystore/Keychain (`flutter_secure_storage`), nunca en preferencias | `data/remote/secure_session_storage.dart` |
| STORAGE-1 | Primera ejecución de una instalación: se borra lo que una instalación anterior dejó en el Keychain (iOS no lo borra al desinstalar) | `data/remote/fresh_install.dart` |
| STORAGE-1 | Cerrar sesión, 401 o refresh rechazado: el estado se limpia antes de la red, el SDK borra los tokens aunque falle, se desregistra el push y se borran las exportaciones LOPDP de la caché | `SessionCubit`, `main.dart`, `SystemFileSharer.clearExports` |
| STORAGE-2 | Sin respaldos ni copia a otro dispositivo (`allowBackup=false`, `fullBackupContent=false`, `data_extraction_rules.xml`) | `AndroidManifest.xml` |
| STORAGE-2 | Logs solo en debug y redactados (JWT, `Bearer`, contraseñas, tokens, correos); nunca montos ni nombres. Sin `print`/`debugPrint`; SDK de Supabase con `debug: false` | `app/logging/app_logger.dart` |
| CRYPTO | Sin criptografía propia: TLS del sistema y almacén seguro de la plataforma | — |
| AUTH | Login por Edge Function (rate limit por dispositivo, captcha opcional); 401 cierra la sesión; acciones destructivas piden contraseña (modo seguro de 5 min) | `ApiClient`, `reauth_sheet.dart` |
| NETWORK-1 | HTTPS obligatorio en staging/prod (`AppConfig` falla al arrancar si no); `cleartextTrafficPermitted=false` y solo CAs del sistema; HTTP únicamente en el flavor `local` hacia 10.0.2.2/localhost | `network_security_config.xml` (`main`, `local`) |
| PLATFORM-1 | Deep links: solo `countit://auth/confirmed` y `/reset-password`; todo lo demás se ignora. El de confirmación no inicia sesión | `app/links/auth_links.dart` |
| PLATFORM-1 | `data` de notificaciones y pushes como no confiable: solo `kind` conocidos, ids enteros positivos de 32 bits, sin rutas ni URLs | `app/router/notification_routes.dart` |
| PLATFORM-2 | WebView del captcha: JS solo para el script de Turnstile; navegación solo a `about:blank`, el origen https configurado y `challenges.cloudflare.com`; sin acceso a archivos ni *content providers*, sin geolocalización, sin contenido mixto, permisos web denegados; solo se aceptan mensajes con forma de token | `shared/widgets/turnstile_field.dart` |
| PLATFORM-3 | `FLAG_SECURE` en toda la app mientras hay sesión (y en la recuperación de contraseña), más las pantallas de login/registro/contraseñas; cortina con el logo en el selector de apps (ambas plataformas) | `SessionSecureScreen`, `SecureScreen`, `PrivacyCurtain` |
| PLATFORM | Única actividad exportada (`MainActivity`, launcher + deep link); `taskAffinity=""` contra *task hijacking*; permisos: `INTERNET` y `POST_NOTIFICATIONS` (pedido desde la bandeja, nunca al arrancar) | `AndroidManifest.xml` |
| CODE-4 | Entradas validadas con los límites del contrato (nombres 1–40/50/100, usernames 3–12, contraseñas 8–72, montos ≤ 12 enteros y 2 decimales, ids saneados en búsquedas `ilike`) | `shared/utils/validators.dart`, `AmountInputFormatter`, repositorios |
| AUTHZ | Roles de solo lectura en la app: `admin_set_user_role` salió de la API (contrato 1.4) y la app no tiene UI, cubit ni repositorio para cambiarlos; solo el dueño los cambia directamente en la BD. Los planes los cambia el superadmin (sin cambiar los propios) | `admin_user_page.dart`, `AdminRepository` |
| LEGAL | Nombres de bancos solo informativos: aviso de no afiliación en el selector de bancos y en «Acerca de Count It!»; el color del banco es un acento atenuado (`mutedBankAccent`: mezcla con la paleta oscura, saturación ≤ 0,35, luminosidad 0,12–0,30, texto blanco ≥ 4,5:1), nunca la imagen del banco | `wallet_colors.dart`, `bank_disclaimer.dart`, `about_page.dart` |
| CODE-1/RESILIENCE | Release ofuscado (`--obfuscate`, R8 minify + shrink), símbolos y mapping fuera del binario; `pubspec.lock` obligatorio en CI | `scripts/build_release.sh`, `proguard-rules.pro` |

## Riesgos residuales
- **iOS sin bloqueo de capturas** (COU-115): iOS no tiene `FLAG_SECURE`; la cortina tapa el selector de apps pero no
  las capturas ni la grabación. Pendiente de la cuenta de Apple para probar la técnica del `UITextField` seguro.
- **Enlaces de esquema propio** (COU-62, COU-132, COU-109): otra app puede registrar `countit://` e interceptar el
  enlace de recuperación (token de un solo uso y de vida corta). Se resuelve con App Links/Universal Links verificados
  cuando haya dominio propio (`assetlinks.json`, `apple-app-site-association`).
- **Sin certificate pinning**: Supabase rota sus certificados (hoy en Cloudflare/AWS) sin aviso y un pin desfasado deja
  la app sin servicio sin poder actualizarla a tiempo. Se mitiga con TLS del sistema, sin CAs de usuario y sin
  *cleartext*; se reconsidera con un dominio propio y una política de rotación (pins de respaldo).
- **Root/jailbreak** (COU-116): sin detección; sería informativa (MASVS-L1 no la exige).
- **Captcha sin activar** (COU-25): sin site key los formularios no muestran Turnstile; quedan el rate limit por
  dispositivo e IP del backend.
- **Enlace de recuperación con sesión activa**: abrirlo reemplaza la sesión actual por la de recuperación (solo
  permite fijar una nueva contraseña de la cuenta del enlace).
- **Escalada de rol**: un rol solo cambia con acceso directo a la BD (dueño del proyecto); queda fuera del alcance de
  un admin o superadmin comprometido en la app. A cambio, promover a alguien exige intervención manual.
- **Marcas de terceros**: los nombres de bancos aparecen en el catálogo; se mitiga con el aviso de no afiliación y
  colores atenuados con la misma tipografía y diseño para todos (sin logos).
- **`--dart-define` legible en el binario**: solo lleva valores públicos (URL, *anon key*, site key).

## Checklist MASVS-L1
- [x] STORAGE-1 datos sensibles solo en almacenamiento seguro · [x] STORAGE-2 sin fugas por logs, respaldos ni caché
- [x] CRYPTO-1/2 sin criptografía propia ni claves en el código
- [x] AUTH-1/2/3 autenticación y autorización en el backend; 401 y cierre de sesión limpian el dispositivo
- [x] NETWORK-1 TLS en todo el tráfico · [ ] NETWORK-2 pinning (riesgo aceptado, ver arriba)
- [x] PLATFORM-1 IPC/deep links/notificaciones validados · [x] PLATFORM-2 WebView restringido
- [x] PLATFORM-3 UI: capturas bloqueadas (Android), cortina en el selector, contraseñas sin sugerencias del teclado
- [x] CODE-1/2/4 dependencias fijadas, versión mínima del SO de Flutter, entradas validadas
- [x] RESILIENCE (L1: no requerido) ofuscación de Dart y R8 · [ ] detección de root (COU-116)
- [x] PRIVACY datos mínimos (los admins no ven finanzas, S-12), exportación y eliminación de cuenta (LOPDP)

Verificación antes de cada release: [`RELEASE.md`](RELEASE.md#verificación-de-seguridad-previa).
