import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/tokens.dart';

/// Lets a form ask the captcha for a fresh token: Turnstile tokens are single
/// use, so the form resets after every attempt, successful or not (COU-83).
class TurnstileController extends ChangeNotifier {
  void reset() => notifyListeners();
}

/// Cloudflare Turnstile inside a webview. [onToken] receives the token when
/// solved and null when it expires or fails. Configuration is validated in
/// `AppConfig` (site key alphabet, https base URL).
///
/// Hardening: JavaScript only for Cloudflare's script, navigation limited to
/// the challenge origin, no file or content access, nothing persisted.
class TurnstileField extends StatefulWidget {
  const TurnstileField({
    super.key,
    required this.siteKey,
    required this.baseUrl,
    required this.controller,
    required this.onToken,
  });

  final String siteKey;
  final Uri baseUrl;
  final TurnstileController controller;
  final ValueChanged<String?> onToken;

  static const _challengeHost = 'challenges.cloudflare.com';

  @visibleForTesting
  static String page(String siteKey) =>
      '''
<!doctype html><html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<script src="https://$_challengeHost/turnstile/v0/api.js?onload=onTurnstileLoad&render=explicit" async defer></script>
<style>html,body{margin:0;background:transparent;display:flex;justify-content:center;align-items:center;height:100%}</style>
</head><body><div id="w"></div><script>
function send(m){Turnstile.postMessage(m)}
function onTurnstileLoad(){window.wid=turnstile.render('#w',{sitekey:'$siteKey',theme:'dark',language:'es',
callback:function(t){send('token:'+t)},'expired-callback':function(){send('expired')},
'error-callback':function(){send('error')},'timeout-callback':function(){send('expired')}});}
function resetTurnstile(){if(window.wid!==undefined){turnstile.reset(window.wid);}}
</script></body></html>''';

  @override
  State<TurnstileField> createState() => _TurnstileFieldState();
}

enum _Status { loading, ready, solved, failed }

class _TurnstileFieldState extends State<TurnstileField> {
  late final WebViewController _web;
  _Status _status = _Status.loading;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('Turnstile', onMessageReceived: (message) => _onMessage(message.message))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _set(_Status.ready),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) _set(_Status.failed);
          },
          onNavigationRequest: (request) {
            final host = Uri.tryParse(request.url)?.host;
            final allowed =
                request.url.startsWith('about:') ||
                host == widget.baseUrl.host ||
                host == TurnstileField._challengeHost;
            return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(TurnstileField.page(widget.siteKey), baseUrl: widget.baseUrl.toString());
    widget.controller.addListener(_reset);
  }

  @override
  void didUpdateWidget(TurnstileField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_reset);
      widget.controller.addListener(_reset);
    }
  }

  void _onMessage(String message) {
    if (message.startsWith('token:')) {
      _set(_Status.solved);
      widget.onToken(message.substring(6));
    } else {
      _set(message == 'error' ? _Status.failed : _Status.ready);
      widget.onToken(null);
    }
  }

  void _reset() {
    widget.onToken(null);
    _set(_Status.ready);
    _web.runJavaScript('resetTurnstile()');
  }

  void _set(_Status status) {
    if (mounted && status != _status) setState(() => _status = status);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_reset);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: switch (_status) {
        _Status.loading => 'Cargando verificación anti-bots',
        _Status.ready => 'Verificación anti-bots',
        _Status.solved => 'Verificación anti-bots completada',
        _Status.failed => 'La verificación anti-bots no cargó',
      },
      container: true,
      child: Column(
        spacing: AppSpacing.sm,
        children: [
          SizedBox(height: 70, child: WebViewWidget(controller: _web)),
          if (_status == _Status.failed)
            TextButton(onPressed: _web.reload, child: const Text('Reintentar verificación')),
        ],
      ),
    );
  }
}

/// The captcha slot of a form: the widget when captcha is configured, nothing
/// otherwise (local, and staging until COU-25), plus the design caption.
class CaptchaSlot extends StatelessWidget {
  const CaptchaSlot({
    super.key,
    required this.siteKey,
    required this.baseUrl,
    required this.controller,
    required this.onToken,
  });

  final String? siteKey;
  final Uri? baseUrl;
  final TurnstileController controller;
  final ValueChanged<String?> onToken;

  @override
  Widget build(BuildContext context) {
    final key = siteKey;
    final base = baseUrl;
    if (key == null || base == null) return const SizedBox.shrink();
    return Column(
      spacing: AppSpacing.sm,
      children: [
        TurnstileField(siteKey: key, baseUrl: base, controller: controller, onToken: onToken),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 6,
          children: [
            const Icon(Icons.shield_outlined, size: 14, color: AppColors.muted),
            Text('Protegido con verificación anti-bots', style: AppTypography.caption.copyWith(color: AppColors.muted)),
          ],
        ),
      ],
    );
  }
}
