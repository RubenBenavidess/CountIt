# Count It! — app móvil (Flutter)

App Android/iOS de finanzas personales con billeteras compartidas. El backend vive en
[CountIt-Backend-Dev](https://github.com/RubenBenavidess/CountIt-Backend-Dev) (Supabase); su contrato está en `docs/API.md`
y `docs/api-schema.json` de ese repositorio. Diseño: lienzo *CountIt App* (tokens en `lib/app/theme/tokens.dart`).

## Requisitos
- Flutter **3.47.6** (stable) · Dart 3.13 · Java 17 para Android.
- Id de paquete: `ec.countit.app` (Android e iOS).

## Ejecutar
```bash
flutter pub get
# Backend local (supabase start en el repo del backend). 10.0.2.2 = el host visto desde el emulador de Android;
# en un teléfono físico, copia env/local.json y usa la IP de tu PC en la red.
flutter run --dart-define-from-file=env/local.json
# Staging: copia env/staging.example.json → env/staging.json (ignorado por git) y complétalo.
flutter run --dart-define-from-file=env/staging.json
```
La configuración solo lleva valores públicos (URL y *anon key* de Supabase). Nada secreto va en la app.

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
