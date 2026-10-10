import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/tokens.dart';

/// Non-affiliation notice for the bank names of the catalogue: shown in the
/// bank picker and in «Acerca de Count It!».
class BankDisclaimer extends StatelessWidget {
  const BankDisclaimer({super.key, this.textAlign = TextAlign.start});

  static const text =
      'Los nombres de bancos se muestran solo para que identifiques tus cuentas y pertenecen a sus '
      'titulares. Count It! no está afiliada ni respaldada por ninguna entidad financiera.';

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      key: const ValueKey('bank-disclaimer'),
      textAlign: textAlign,
      style: AppTypography.caption.copyWith(fontSize: 12, color: context.palette.muted),
    );
  }
}
