# Sitio web de Count It!

Publicado en **https://countit-bft.pages.dev** (proyecto `countit` en la cuenta de Cloudflare de Ruben; dominio gratuito de Pages para la beta). Fuente: carpeta `site/` en la raíz del repo.

Sitio estático (HTML + CSS, **sin JavaScript**) que se publica en Cloudflare Pages. Contiene:

| Ruta | Archivo | Para qué |
|---|---|---|
| `/` | `index.html` | Portada mínima con enlaces a los documentos legales |
| `/privacidad/` | `privacidad/index.html` | Política de privacidad (exigida por Google Play y App Store) |
| `/terminos/` | `terminos/index.html` | Términos de uso |
| `/auth/confirmed` | `auth/confirmed/index.html` | Respaldo del enlace de confirmación de correo cuando la app no está instalada |
| `/auth/reset-password` | `auth/reset-password/index.html` | Respaldo del enlace de recuperación de contraseña cuando la app no está instalada |
| `/.well-known/assetlinks.json` | `.well-known/assetlinks.json` | Digital Asset Links (Android App Links) |
| — | `_headers` | Cabeceras de Cloudflare Pages (CSP estricta, HSTS, `no-store` en `/auth/*`) |
| — | `404.html` | Página de error |

Con la app instalada, Android abre `/auth/*` directamente en la app (App Links verificados); las páginas de
`auth/` solo se ven en dispositivos sin la app.

## Reglas
- **Sin JavaScript, fuentes externas, analítica ni recursos de terceros** en ninguna página. La CSP de `_headers`
  (`default-src 'none'`) lo hace cumplir: cualquier `<script>` o recurso externo queda bloqueado.
- La página de recuperación recibe tokens en el fragmento de la URL (`#access_token=…`): nunca debe leerlo,
  mostrarlo, guardarlo ni reenviarlo. Por eso es HTML puro, con `<meta name="referrer" content="no-referrer">`.
- Enlaces solo relativos (sin dominio fijo).
- Textos en español (es-EC, tuteo); código y comentarios en inglés.
- Antes de publicar, reemplazar los marcadores `[[RESPONSABLE]]` y `[[CORREO_DE_CONTACTO]]` en
  `privacidad/index.html` y `terminos/index.html`:
  ```bash
  grep -rn '\[\[' site/
  ```

## Vista previa local
```bash
python3 -m http.server -d site 8000
# http://localhost:8000
```
El servidor de Python no aplica `_headers` ni sirve `404.html`; eso solo ocurre en Cloudflare Pages.

## Despliegue (Cloudflare Pages)
```bash
npx wrangler@4.20.0 pages deploy site --project-name countit --branch main
```
La primera vez, iniciar sesión en Cloudflare (`npx wrangler@4.20.0 login`). Todo lo que hay en `site/` se publica:
no dejar ahí borradores ni documentación. Con dominio propio, asociarlo en el panel (Workers & Pages → `countit` →
Custom domains), agregarlo a `assetlinks.json`/manifiesto y a las redirect URLs de Auth.

Comprobar tras desplegar:
```bash
curl -sI https://countit-bft.pages.dev/ | grep -i -E 'content-security-policy|strict-transport|referrer-policy'
curl -sI https://countit-bft.pages.dev/.well-known/assetlinks.json | grep -i -E 'content-type|access-control'
curl -sI https://countit-bft.pages.dev/auth/reset-password/ | grep -i cache-control
```
`assetlinks.json` debe responder `200` directamente (sin redirecciones) y con `Content-Type: application/json`.

## Agregar la huella de producción
Hoy `assetlinks.json` solo declara `ec.countit.app.staging` (llave de depuración usada en los builds de staging).
Cuando exista el keystore de release:

1. Obtener la huella SHA-256 del certificado de firma:
   ```bash
   keytool -list -v -keystore <ruta/al/release.jks> -alias <alias> | grep SHA256
   ```
   Si la app se publica con **Play App Signing**, la huella que vale es la de la *llave de firma de apps* que muestra
   Play Console (Configuración → Integridad de la app), no la de la llave de subida.
2. Agregar un segundo objeto al arreglo de `site/.well-known/assetlinks.json`:
   ```json
   {
     "relation": ["delegate_permission/common.handle_all_urls"],
     "target": {
       "namespace": "android_app",
       "package_name": "ec.countit.app",
       "sha256_cert_fingerprints": ["AA:BB:…"]
     }
   }
   ```
3. Volver a desplegar y verificar (abajo).

## Verificar App Links
```bash
# Lo que Google lee del sitio
curl -s 'https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://countit-bft.pages.dev&relation=delegate_permission/common.handle_all_urls'

# Estado de verificación en un dispositivo con la app de staging instalada
adb shell pm get-app-links ec.countit.app.staging
# Forzar una nueva verificación (Android 12+)
adb shell pm verify-app-links --re-verify ec.countit.app.staging
```
El dominio debe aparecer como `verified`. Si sale `1024` u otro código, revisar que la huella y el paquete
coincidan y que `assetlinks.json` responda sin redirecciones.
