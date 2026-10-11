/// Deployment target the build points to.
enum AppEnvironment {
  local,
  staging,
  prod;

  static AppEnvironment parse(String value) => AppEnvironment.values.firstWhere(
    (e) => e.name == value,
    orElse: () => throw ArgumentError.value(value, 'APP_ENV', 'expected local, staging or prod'),
  );
}

/// Build-time configuration, injected with `--dart-define-from-file=env/<env>.json`.
///
/// The Supabase URL and anon key are public by design (every request carries
/// them); nothing secret may ever be added here.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.turnstileSiteKey,
    this.turnstileBaseUrl,
  });

  /// Reads the compile-time defines; fails fast when a build forgot them.
  factory AppConfig.fromEnvironment() {
    const env = String.fromEnvironment('APP_ENV');
    const url = String.fromEnvironment('SUPABASE_URL');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    const turnstile = String.fromEnvironment('TURNSTILE_SITE_KEY');
    const turnstileBase = String.fromEnvironment('TURNSTILE_BASE_URL');
    return AppConfig.fromValues(
      env: env,
      url: url,
      anonKey: anonKey,
      turnstileSiteKey: turnstile,
      turnstileBaseUrl: turnstileBase,
    );
  }

  /// Validates raw values (used by [AppConfig.fromEnvironment] and tests).
  factory AppConfig.fromValues({
    required String env,
    required String url,
    required String anonKey,
    String turnstileSiteKey = '',
    String turnstileBaseUrl = '',
  }) {
    if (env.isEmpty || url.isEmpty || anonKey.isEmpty) {
      throw StateError('Missing build configuration: run with --dart-define-from-file=env/<local|staging|prod>.json');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(url, 'SUPABASE_URL', 'not an absolute URL');
    }
    final environment = AppEnvironment.parse(env);
    if (environment != AppEnvironment.local && uri.scheme != 'https') {
      throw ArgumentError.value(url, 'SUPABASE_URL', 'staging and prod require https');
    }
    Uri? captchaBase;
    if (turnstileSiteKey.isNotEmpty) {
      // The key is interpolated into the widget page: only Cloudflare's alphabet.
      if (!RegExp(r'^[0-9A-Za-z_-]{1,100}$').hasMatch(turnstileSiteKey)) {
        throw ArgumentError.value(turnstileSiteKey, 'TURNSTILE_SITE_KEY', 'invalid site key');
      }
      captchaBase = Uri.tryParse(turnstileBaseUrl);
      if (captchaBase == null || captchaBase.scheme != 'https' || captchaBase.host.isEmpty) {
        throw ArgumentError.value(
          turnstileBaseUrl,
          'TURNSTILE_BASE_URL',
          'https URL of a hostname allowed in Turnstile',
        );
      }
    }
    return AppConfig(
      environment: environment,
      supabaseUrl: url,
      supabaseAnonKey: anonKey,
      turnstileSiteKey: turnstileSiteKey.isEmpty ? null : turnstileSiteKey,
      turnstileBaseUrl: captchaBase,
    );
  }

  final AppEnvironment environment;
  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Cloudflare Turnstile site key (public). Null while Auth has no captcha
  /// enabled (local, and staging until COU-25); then the app skips the widget.
  final String? turnstileSiteKey;

  /// Origin the widget page is loaded under; Turnstile only issues tokens for
  /// hostnames listed in its site settings.
  final Uri? turnstileBaseUrl;

  bool get captchaEnabled => turnstileSiteKey != null;

  bool get isProduction => environment == AppEnvironment.prod;

  /// Host of the verified App Links that Supabase Auth e-mails point to
  /// (`https://<host>/auth/confirmed`, `/auth/reset-password`; COU-62, COU-109).
  /// Must match `authLinkHost` in `android/app/build.gradle.kts` and the site that
  /// serves `/.well-known/assetlinks.json`. Optional define; the beta uses Pages.
  static const authLinkHost = String.fromEnvironment('AUTH_LINK_HOST', defaultValue: 'countit-bft.pages.dev');
}
