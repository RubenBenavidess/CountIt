import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/session/session_cubit.dart';
import '../../../app/theme/tokens.dart';
import '../../../data/dtos/profile.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/app_banner.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_fields.dart';
import '../../../shared/widgets/app_layout.dart';
import '../cubit/profile_cubits.dart';
import 'timezone_picker.dart';

/// «Datos personales» (HU-05 · COU-144, COU-145, COU-146).
class EditProfilePage extends StatelessWidget {
  const EditProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.read<SessionCubit>().state.profile;
    if (profile == null) return const Scaffold(body: LoadingView());
    return BlocProvider(
      create: (context) =>
          EditProfileCubit(profiles: context.read<ProfileRepository>(), session: context.read<SessionCubit>()),
      child: _EditProfileView(profile: profile),
    );
  }
}

class _EditProfileView extends StatefulWidget {
  const _EditProfileView({required this.profile});

  final Profile profile;

  @override
  State<_EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<_EditProfileView> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName = TextEditingController(text: widget.profile.firstName ?? '');
  late final _lastName = TextEditingController(text: widget.profile.lastName ?? '');
  late final _username = TextEditingController(text: widget.profile.username);
  late String _timezone = widget.profile.timezone;

  /// Recomputed only when a field changes, to enable «Guardar» and guard «atrás».
  late final _dirty = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    for (final c in [_firstName, _lastName, _username]) {
      c.addListener(_updateDirty);
    }
  }

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _username]) {
      c.dispose();
    }
    _dirty.dispose();
    super.dispose();
  }

  void _updateDirty() {
    final p = widget.profile;
    _dirty.value =
        _firstName.text.trim() != (p.firstName ?? '') ||
        _lastName.text.trim() != (p.lastName ?? '') ||
        _username.text.trim() != p.username ||
        _timezone != p.timezone;
  }

  Future<void> _pickTimezone() async {
    final picked = await pickTimezone(context, current: _timezone);
    if (picked != null) {
      setState(() => _timezone = picked);
      _updateDirty();
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await context.read<EditProfileCubit>().save(
      original: widget.profile,
      firstName: _firstName.text,
      lastName: _lastName.text,
      username: _username.text,
      timezone: _timezone,
    );
    if (ok && mounted) {
      _dirty.value = false;
      showAppSnackBar(context, 'Guardamos tus datos', kind: SnackKind.success);
      context.pop();
    }
  }

  Future<void> _confirmLeave() async {
    final navigator = GoRouter.of(context);
    final leave = await showConfirmDialog(
      context,
      title: '¿Descartar los cambios?',
      message: 'Tienes cambios sin guardar.',
      confirmLabel: 'Descartar',
      cancelLabel: 'Seguir editando',
      destructive: true,
    );
    if (leave) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _dirty,
      builder: (context, dirty, child) => PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: child!,
      ),
      child: Scaffold(
        appBar: const AppTopBar(title: 'Datos personales'),
        body: BlocBuilder<EditProfileCubit, SubmitState>(
          builder: (context, state) {
            final failure = state.failure;
            final usernameError = switch (failure?.key) {
              'username_taken' || 'invalid_username' => failure!.message,
              _ => null,
            };
            return Form(
              key: _formKey,
              child: FormScreenBody(
                content: [
                  if (failure != null && usernameError == null)
                    AppBanner(tone: BannerTone.error, message: failure.message),
                  AppTextField(
                    label: 'Nombre',
                    controller: _firstName,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 40,
                    validator: (v) => Validators.personName(v),
                    enabled: !state.submitting,
                  ),
                  AppTextField(
                    label: 'Apellido',
                    controller: _lastName,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 40,
                    validator: (v) => Validators.personName(v, label: 'apellido'),
                    enabled: !state.submitting,
                  ),
                  AppTextField(
                    label: 'Nombre de usuario',
                    controller: _username,
                    helper: '5 a 12 caracteres: letras, números, - y _. Así te invitan a familias.',
                    maxLength: 12,
                    validator: Validators.username,
                    errorText: usernameError,
                    enabled: !state.submitting,
                    onChanged: (_) => context.read<EditProfileCubit>().clearFailure(),
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.xs),
                      child: Text('@', style: TextStyle(fontSize: 16, color: AppColors.muted)),
                    ),
                  ),
                  _TimezoneField(value: _timezone, enabled: !state.submitting, onTap: _pickTimezone),
                ],
                footer: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _dirty,
                    builder: (context, dirty, _) =>
                        AppButton(label: 'Guardar', loading: state.submitting, onPressed: dirty ? _save : null),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TimezoneField extends StatelessWidget {
  const _TimezoneField({required this.value, required this.enabled, required this.onTap});

  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        Text('Zona horaria', style: AppTypography.label.copyWith(color: Theme.of(context).colorScheme.onSurface)),
        Semantics(
          button: true,
          label: 'Zona horaria: $value',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            onTap: enabled ? onTap : null,
            child: InputDecorator(
              decoration: const InputDecoration(
                helperText: 'Define tu «hoy» para fechas y periodos.',
                suffixIcon: Icon(Icons.expand_more_rounded),
              ),
              child: Text(value.replaceAll('_', ' '), style: AppTypography.body.copyWith(fontSize: 16)),
            ),
          ),
        ),
      ],
    );
  }
}
