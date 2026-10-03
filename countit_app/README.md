# Count It! — app móvil (Flutter)

App Android/iOS de finanzas personales con billeteras compartidas. El backend vive en
[CountIt-Backend-Dev](https://github.com/RubenBenavidess/CountIt-Backend-Dev) (Supabase); su contrato está en `docs/API.md`
y `docs/api-schema.json` de ese repositorio. Diseño: lienzo *CountIt App* (tokens en `lib/app/theme/tokens.dart`).

## Requisitos
- Flutter **3.47.6** (stable) · Dart 3.13 · Java 17 para Android.
- Id de paquete: `ec.countit.app` (Android e iOS).

## Ejecutar
Cada entorno es un *flavor* con su propio id e ícono de nombre, así pueden convivir instaladas:

| Flavor | Android id | Nombre | Config |
|---|---|---|---|
| `local` | `ec.countit.app.local` | Count It! Local | `env/local.json` (versionado) |
| `staging` | `ec.countit.app.staging` | Count It! Staging | `env/staging.json` (copiar de `staging.example.json`; ignorado por git) |
| `prod` | `ec.countit.app` | Count It! | `env/prod.json` (ignorado por git) |

```bash
flutter pub get
# Backend local (supabase start en el repo del backend). 10.0.2.2 = el host visto desde el emulador de Android;
# en un teléfono físico, copia env/local.json y usa la IP de tu PC en la red.
flutter run --flavor local --dart-define-from-file=env/local.json
flutter run --flavor staging --dart-define-from-file=env/staging.json
```
La configuración solo lleva valores públicos: URL y *anon key* de Supabase y, cuando se active el captcha (COU-25),
`TURNSTILE_SITE_KEY`. Nada secreto va en la app. Los flavors de iOS (schemes y xcconfig) quedan pendientes: requieren
Xcode para crearlos y verificarlos.

## Calidad
```bash
dart format lib test          # ancho 120 (analysis_options.yaml)
flutter analyze
flutter test
```
CI (`.github/workflows/flutter.yml`): formato, análisis, tests y build de APK debug en cada PR.

## Arquitectura
Capas `app/` (composición: config, tema, router, errores, sesión), `data/` (clientes y repositorios),
`presentation/` (features con View + Cubit) y `shared/` (componentes reutilizables). Estado con **flutter_bloc**.
Cada carpeta tiene su README con reglas.
