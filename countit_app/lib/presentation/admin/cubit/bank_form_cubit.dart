import '../../../data/dtos/bank.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/state/submit_cubit.dart';
import 'admin_failures.dart';

/// Create or edit a bank (HU-27 · COU-206). Mirrors the backend rules so the
/// form answers at once; the API validates again (unique name, 409).
class BankFormCubit extends SubmitCubit {
  BankFormCubit(this._admin, {this.bankId});

  final AdminRepository _admin;

  /// The bank being edited; null when creating.
  final int? bankId;

  static const nameMax = 100;
  static final _country = RegExp(r'^[A-Z]{2}$');

  /// The saved bank (set on success).
  Bank? saved;

  static String? validateName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Este campo no puede quedar vacío';
    return text.length > nameMax ? 'Máximo de caracteres alcanzado ($nameMax) en el nombre' : null;
  }

  static String? validateCountry(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Este campo no puede quedar vacío';
    return _country.hasMatch(text) ? null : 'Usa 2 letras mayúsculas (ISO 3166-1, p. ej. EC)';
  }

  Future<bool> save(BankInput input) async {
    final ok = await submit(() async {
      final id = bankId;
      saved = id == null ? await _admin.createBank(input) : await _admin.updateBank(id, input);
    });
    if (!ok && state.failure != null && !isClosed) {
      final neutral = adminFailure(state.failure!);
      if (neutral != state.failure) fail(neutral.message);
    }
    return ok;
  }
}
