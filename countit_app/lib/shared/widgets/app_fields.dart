import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import 'motion.dart';

/// Label above the control, as in the design (14 px, semibold).
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: Theme.of(context).colorScheme.onSurface)),
        child,
      ],
    );
  }
}

/// Text input with label, helper and error text (error replaces the helper).
///
/// Inside a `Form`, [validator] runs after the user touches the field and on
/// `FormState.validate()`. [errorText] forces a message regardless (e.g. the
/// server's `validationErrors` for this field).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.hint,
    this.helper,
    this.errorText,
    this.validator,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.maxLength,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final String? helper;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Style of the typed value.
  static final inputStyle = AppTypography.body.copyWith(fontSize: 16);

  @override
  Widget build(BuildContext context) {
    return _Labeled(
      label: label,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        obscureText: obscureText,
        // Secrets never go to the keyboard's dictionary or suggestions.
        autocorrect: !obscureText,
        enableSuggestions: !obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        autofillHints: autofillHints,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        forceErrorText: errorText,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        style: inputStyle,
        decoration: InputDecoration(
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          errorMaxLines: 3,
          prefixIcon: prefix,
          suffixIcon: suffix,
          counterText: '',
          semanticCounterText: '',
        ),
      ),
    );
  }
}

/// Password input with a show/hide toggle.
class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    super.key,
    this.label = 'Contraseña',
    this.controller,
    this.focusNode,
    this.errorText,
    this.helper,
    this.validator,
    this.enabled = true,
    this.newPassword = false,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? errorText;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;

  /// Autofill hint: a new password (registration, change) vs the current one.
  final bool newPassword;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      controller: widget.controller,
      focusNode: widget.focusNode,
      errorText: widget.errorText,
      helper: widget.helper,
      validator: widget.validator,
      enabled: widget.enabled,
      obscureText: !_visible,
      textInputAction: widget.textInputAction,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffix: IconButton(
        tooltip: _visible ? 'Ocultar contraseña' : 'Mostrar contraseña',
        icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        onPressed: widget.enabled ? () => setState(() => _visible = !_visible) : null,
      ),
    );
  }
}

/// Only digits and one decimal separator (dot or comma) with at most 2
/// decimals: the API rejects more (400 invalid_amount).
class AmountInputFormatter extends TextInputFormatter {
  static final _valid = RegExp(r'^\d{0,12}([.,]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      _valid.hasMatch(newValue.text) ? newValue : oldValue;
}

/// USD amount input («$» prefix, decimal keyboard, max 2 decimals).
/// Read the value with `Money.parse(controller.text)`.
///
/// [AppMoneyField.hero] is the large, centred variant where the amount is the
/// protagonist of the form (movements, scheduled movements): display type in
/// the colour of its kind, with the sign always visible.
class AppMoneyField extends StatelessWidget {
  const AppMoneyField({
    super.key,
    this.label = 'Monto',
    this.controller,
    this.errorText,
    this.helper,
    this.enabled = true,
    this.onChanged,
  }) : income = null;

  /// Large amount signed and coloured by kind: `+$` in `palette.income` or
  /// `−$` in `palette.expense`. Colour and sign animate when [income] changes.
  const AppMoneyField.hero({
    super.key,
    required bool this.income,
    this.label = 'Monto',
    this.controller,
    this.errorText,
    this.helper,
    this.enabled = true,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? errorText;
  final String? helper;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  /// Kind of the hero variant; null in the regular field.
  final bool? income;

  /// Style of the «$» prefix: the input's style ([AppTextField]) in bold.
  static final prefixStyle = AppTextField.inputStyle.copyWith(fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final income = this.income;
    if (income != null) {
      return _HeroMoneyField(
        label: label,
        income: income,
        controller: controller,
        errorText: errorText,
        helper: helper,
        enabled: enabled,
        onChanged: onChanged,
      );
    }
    return AppTextField(
      label: label,
      controller: controller,
      errorText: errorText,
      helper: helper,
      enabled: enabled,
      hint: '0,00',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [AmountInputFormatter()],
      onChanged: onChanged,
      // The decorator gives prefix icons a 48 px minimum height: without the
      // Center the «$» would paint at the top of that box, above the value.
      // Same font, size and line height as the input so both share a baseline.
      prefix: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.xs),
        child: Center(widthFactor: 1, child: Text(r'$', style: AppMoneyField.prefixStyle)),
      ),
    );
  }
}

class _HeroMoneyField extends StatefulWidget {
  const _HeroMoneyField({
    required this.label,
    required this.income,
    required this.controller,
    required this.errorText,
    required this.helper,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool income;
  final TextEditingController? controller;
  final String? errorText;
  final String? helper;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  State<_HeroMoneyField> createState() => _HeroMoneyFieldState();
}

class _HeroMoneyFieldState extends State<_HeroMoneyField> {
  /// Display type of the design (Manrope 44, extra bold) with tabular figures.
  static final style = AppTypography.display.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Long amounts shrink down to this size, then scroll inside the field.
  static const minFontSize = 22.0;

  /// Room for the caret after the last digit.
  static const caretSlack = 8.0;

  static const placeholder = '0,00';

  TextEditingController? _own;
  final _focus = FocusNode();

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  @override
  void dispose() {
    _focus.dispose();
    _own?.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  double _width(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.of(context, AppMotion.medium);
    final color = widget.income ? palette.income : palette.expense;
    final sign = widget.income ? '+' : Money.minus;
    final kind = widget.income ? 'ingreso' : 'gasto';
    final error = widget.errorText;
    final scaler = MediaQuery.textScalerOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        ExcludeSemantics(
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: AppTypography.label.copyWith(color: palette.muted),
          ),
        ),
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: duration,
          curve: AppMotion.standard,
          builder: (context, animated, _) => ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final text = _controller.text;
                final shown = text.isEmpty ? placeholder : text;
                // Shrink the type until sign, «$» and digits fit on one line.
                final prefix = '$sign\$';
                final natural = _width(prefix, style, scaler) + _width(shown, style, scaler) + caretSlack;
                final fit = natural <= constraints.maxWidth ? 1.0 : constraints.maxWidth / natural;
                final fontSize = (style.fontSize! * fit).clamp(minFontSize, style.fontSize!);
                final sized = style.copyWith(fontSize: fontSize, color: animated);
                final prefixWidth = _width(prefix, sized, scaler);
                final fieldWidth = (_width(shown, sized, scaler) + caretSlack).clamp(
                  caretSlack,
                  (constraints.maxWidth - prefixWidth).clamp(caretSlack, double.infinity),
                );
                final value = text.isEmpty ? 'vacío' : '$text dólares';
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: widget.enabled ? _focus.requestFocus : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      ExcludeSemantics(
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: Text(prefix, key: ValueKey(prefix), style: sized),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: MergeSemantics(
                          child: Semantics(
                            label: '${widget.label}, $kind',
                            value: value,
                            child: TextField(
                              key: const ValueKey('hero-amount-input'),
                              controller: _controller,
                              focusNode: _focus,
                              enabled: widget.enabled,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [AmountInputFormatter()],
                              onChanged: widget.onChanged,
                              style: sized,
                              cursorColor: animated,
                              maxLines: 1,
                              decoration:
                                  InputDecoration.collapsed(
                                    hintText: placeholder,
                                    hintStyle: sized.copyWith(color: AppColors.placeholder),
                                  ).copyWith(
                                    // The theme's input box would frame the digits: the
                                    // underline below shows focus and errors instead.
                                    filled: false,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        // Focus and error state, like the border of the other inputs.
        Center(
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.fast),
            width: 120,
            height: 2,
            decoration: BoxDecoration(
              color: error != null
                  ? palette.expense
                  : _focus.hasFocus
                  ? scheme.primary
                  : palette.line,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
        ),
        if (error != null)
          Text(
            error,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: palette.expense),
          )
        else if (widget.helper != null)
          Text(
            widget.helper!,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: palette.muted),
          ),
      ],
    );
  }
}

/// Read-only field that opens the date picker (Spanish, Monday first).
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.errorText,
    this.enabled = true,
    this.placeholder = 'Selecciona una fecha',
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? errorText;
  final bool enabled;
  final String placeholder;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _clamp(value ?? DateTime.now()),
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('es', 'EC'),
    );
    if (picked != null) onChanged(DateTime(picked.year, picked.month, picked.day));
  }

  /// showDatePicker asserts that the initial date is within [firstDate, lastDate].
  DateTime _clamp(DateTime day) => day.isBefore(firstDate)
      ? firstDate
      : day.isAfter(lastDate)
      ? lastDate
      : day;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? placeholder : Dates.date(value!);
    return _Labeled(
      label: label,
      child: Semantics(
        button: true,
        // Its own node: never merged with help texts around the field.
        container: true,
        // The error is read too: excludeSemantics hides the decorator's text.
        label: errorText == null ? '$label: $text' : '$label: $text. $errorText',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: enabled ? () => _pick(context) : null,
          child: InputDecorator(
            isEmpty: value == null,
            decoration: InputDecoration(
              errorText: errorText,
              enabled: enabled,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
            ),
            child: Text(
              text,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                color: value == null ? AppColors.placeholder : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An option of [AppDropdownField].
class AppOption<T> {
  const AppOption(this.value, this.label);

  final T value;
  final String label;
}

/// Labeled dropdown (bank, wallet type, budget…).
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint = 'Selecciona una opción',
    this.errorText,
    this.enabled = true,
  });

  final String label;
  final List<AppOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String hint;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _Labeled(
      label: label,
      child: DropdownButtonFormField<T>(
        // initialValue is only read once; the key rebuilds the field when the
        // parent changes the value (e.g. a form reset or a pre-filled edit).
        key: ValueKey<T?>(value),
        initialValue: value,
        isExpanded: true,
        hint: Text(hint, style: AppTypography.body.copyWith(color: AppColors.placeholder)),
        decoration: InputDecoration(errorText: errorText, enabled: enabled),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        items: [
          for (final option in options)
            DropdownMenuItem<T>(
              value: option.value,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// Labeled single choice as chips (budget type, period…): every option
/// visible at once, one tap to pick. [helper] explains the current choice.
class AppChoiceChips<T> extends StatelessWidget {
  const AppChoiceChips({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.helper,
    this.errorText,
    this.enabled = true,
  });

  final String label;
  final List<AppOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? helper;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final error = errorText;
    return _Labeled(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.sm,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final option in options)
                ChoiceChip(
                  key: ValueKey('choice-${option.value}'),
                  label: Text(option.label),
                  selected: option.value == value,
                  onSelected: enabled ? (_) => onChanged(option.value) : null,
                ),
            ],
          ),
          if (error != null)
            Text(error, style: AppTypography.caption.copyWith(color: Theme.of(context).colorScheme.error))
          else if (helper != null)
            Text(helper!, style: AppTypography.caption.copyWith(color: muted)),
        ],
      ),
    );
  }
}
