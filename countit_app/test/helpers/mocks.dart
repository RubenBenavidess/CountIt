import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:countit_app/data/repositories/bank_repository.dart';
import 'package:countit_app/data/repositories/budget_repository.dart';
import 'package:countit_app/data/repositories/profile_repository.dart';
import 'package:countit_app/data/repositories/wallet_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';

/// Shared mocktail doubles. Repositories are the seam for widget and Cubit
/// tests; mock [ApiClient] only to test repositories themselves.
class MockAuthRepository extends Mock implements AuthRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockWalletRepository extends Mock implements WalletRepository {}

class MockBankRepository extends Mock implements BankRepository {}

class MockBudgetRepository extends Mock implements BudgetRepository {}

class MockApiClient extends Mock implements ApiClient {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}
