# Release de la app (COU-49)

Checklist para publicar una versión de Count It! en Google Play (y, cuando exista la cuenta de Apple, en App Store).
La firma, el script de build y el workflow están descritos en el [README](../README.md#release).

## Versionado
`pubspec.yaml` → `version: MAJOR.MINOR.PATCH+BUILD` (p. ej. `1.2.0+14`).

- **MAJOR.MINOR.PATCH** (semver) es el `versionName` / `CFBundleShortVersionString` que ve el usuario:
  - MAJOR: cambio incompatible para el usuario o que exige una versión mínima del backend.
  - MINOR: funcionalidad nueva compatible.
  - PATCH: correcciones sin funcionalidad nueva.
- **BUILD** es el `versionCode` / `CFBundleVersion`: entero que **sube en cada build subido a una tienda**, aunque el
  semver no cambie (Play rechaza un `versionCode` repetido o menor). Nunca se reinicia.
- Los flavors añaden sufijo al nombre (`-local`, `-staging`); `prod` no lleva sufijo.
- Tag de git por versión publicada: `v1.2.0+14` (dispara `.github/workflows/android-release.yml`).
- Antes de 1.0.0 la app está en pruebas internas; `1.0.0` es la primera versión pública.

## Pasos
1. **Rama al día:** `main` con el CI verde (`flutter.yml`).
2. **Versión:** subir `version:` en `pubspec.yaml` (semver según los cambios y BUILD + 1) en un PR
   `chore(app): versión x.y.z+N`, con las notas de la versión en la descripción.
3. **Verificación de seguridad** (abajo) completa, marcada en el PR.
4. **Fusionar y etiquetar:** `git tag v<x.y.z+N> && git push origin v<x.y.z+N>`.
5. **Build:** el workflow *Android release* construye el `appbundle` de `prod` firmado. Comprobar en el log que **no**
   aparece el aviso «Release build skipped». En local: `scripts/build_release.sh prod appbundle`.
6. **Archivar** los artifacts `symbols-prod` (símbolos Dart + `mapping.txt` de R8) en almacenamiento privado,
   nombrados por versión. Sin ellos no se pueden leer los *stack traces* (`flutter symbolize`).
7. **Subir** el `.aab` a la pista de pruebas internas de Play (COU-185) y adjuntar `mapping.txt` en Play Console
   (*App bundle explorer → Downloads → ReTrace mapping file*).
8. **Prueba de humo** en un dispositivo real desde Play: registro/login, billetera, transacción, notificaciones, cerrar
   sesión. Revisar que el ícono, el nombre «Count It!» y el splash son los de producción.
9. **Promover** a producción por etapas (p. ej. 10 % → 50 % → 100 %) vigilando los fallos en Play Console.
10. **Cerrar:** comentar la versión en los issues de Linear incluidos y moverlos a *Done*.

## Verificación de seguridad previa
- [ ] **Sin logs sensibles:** el logger solo escribe en debug (`AppLogger`, `kDebugMode`) y oculta tokens, contraseñas
  y correos; no hay `print`/`debugPrint` nuevos (`grep -rn "print(" lib`).
- [ ] **Ofuscación:** el build usa `--obfuscate --split-debug-info` (Dart) y R8 (`isMinifyEnabled`,
  `isShrinkResources`); los símbolos y el mapping quedan fuera del `.aab` y del repositorio.
- [ ] **Flavor correcto:** se publica `prod` (`ec.countit.app`, «Count It!») con `env/prod.json` de producción; nunca
  `local` (permite HTTP hacia el emulador) ni `staging`.
- [ ] **Solo claves públicas:** `env/prod.json` contiene únicamente `SUPABASE_URL`, la *anon key* y, si aplica,
  `TURNSTILE_SITE_KEY`/`TURNSTILE_BASE_URL`. Ninguna `service_role`, token o secreto (`--dart-define` queda legible
  en el binario).
- [ ] **Firma:** `.aab` firmado con la clave de subida (no la debug): `jarsigner -verify -verbose -certs <aab>` o el
  aviso de Play. El keystore y sus contraseñas solo en el gestor de contraseñas y en los secretos de GitHub.
- [ ] **Permisos del manifest:** revisar el manifest fusionado (`build/app/intermediates/merged_manifests/prodRelease/`
  o `aapt dump permissions` del APK). Hoy: solo `INTERNET` (y el permiso interno `DYNAMIC_RECEIVER_NOT_EXPORTED`).
  Cualquier permiso nuevo de un plugin se justifica o se elimina con `tools:node="remove"`, y se refleja en el
  formulario *Data safety* (COU-139).
- [ ] **Red:** `network_security_config` de `main` sin *cleartext* ni CAs de usuario; `allowBackup=false`.
- [ ] **Dependencias:** `pubspec.lock` versionado; sin avisos de seguridad abiertos de Dependabot.
- [ ] **Backend:** la versión mínima de la API que usa la app ya está desplegada en producción.

## iOS (pendiente)
Requiere la cuenta de Apple Developer (COU-45), flavors en Xcode (ver README) y `scripts/build_release.sh prod ipa`
en macOS. Mismas reglas de versión: `CFBundleShortVersionString` = semver y `CFBundleVersion` = BUILD.
