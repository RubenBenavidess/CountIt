import 'package:countit_app/data/remote/api_client.dart';
import 'package:countit_app/data/repositories/analysis_repository.dart';
import 'package:countit_app/data/repositories/auth_repository.dart';
import 'package:countit_app/data/repositories/bank_repository.dart';
import 'package:countit_app/data/repositories/budget_repository.dart';
import 'package:countit_app/data/repositories/family_repository.dart';
import 'package:countit_app/data/repositories/profile_repository.dart';
import 'package:countit_app/data/repositories/scheduled_transaction_repository.dart';
import 'package:countit_app/data/repositories/transaction_repository.dart';
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

class MockTransactionRepository extends Mock implements TransactionRepository {}

class MockScheduledTransactionRepository extends Mock implements ScheduledTransactionRepository {}

class MockFamilyRepository extends Mock implements FamilyRepository {}

class MockAnalysisRepository extends Mock implements AnalysisRepository {}

class MockApiClient extends Mock implements ApiClient {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}
