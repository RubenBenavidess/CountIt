import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/tokens.dart';
import '../utils/dates.dart';

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
class AppMoneyField extends StatelessWidget {
  const AppMoneyField({
    super.key,
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

  /// Style of the «$» prefix: the input's style ([AppTextField]) in bold.
  static final prefixStyle = AppTextField.inputStyle.copyWith(fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
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
