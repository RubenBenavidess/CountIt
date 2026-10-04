import '../../../app/errors/app_failure.dart';

/// Neutral text for a 403 in the admin area: it never says which role or
/// rule refused the action.
const adminForbiddenMessage = 'No tienes permiso para realizar esta acción.';

/// [failure] with the neutral message when the role refused it (403 `forbidden`).
AppFailure adminFailure(AppFailure failure) => failure.kind == FailureKind.forbidden
    ? AppFailure(kind: FailureKind.forbidden, message: adminForbiddenMessage, key: failure.key, status: failure.status)
    : failure;
