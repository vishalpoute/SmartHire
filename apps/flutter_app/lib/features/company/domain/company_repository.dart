import 'company.dart';

abstract interface class CompanyRepository {
  Future<SavedCompany?> load();
  Future<SavedCompany> save(CompanyDraft draft);
}

class CompanyFailure implements Exception {
  const CompanyFailure(this.message);
  final String message;
}
