import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/company.dart';
import '../domain/company_repository.dart';

enum CompanyStatus { initial, loading, ready, saving, saved, failure }

class CompanyState {
  const CompanyState({
    required this.status,
    required this.draft,
    this.approval,
    this.message,
    this.errors = const {},
  });
  final CompanyStatus status;
  final CompanyDraft draft;
  final CompanyApproval? approval;
  final String? message;
  final Map<String, String> errors;
}

/// Scoped to one signed-in screen; closing/resetting invalidates pending results.
class CompanyCubit extends Cubit<CompanyState> {
  CompanyCubit(this.repository)
    : super(
        const CompanyState(
          status: CompanyStatus.initial,
          draft: CompanyDraft(name: ''),
        ),
      );
  final CompanyRepository repository;
  int _generation = 0;
  bool get busy =>
      state.status == CompanyStatus.loading ||
      state.status == CompanyStatus.saving;

  void edit(CompanyDraft draft) {
    if (isClosed || busy) return;
    emit(
      CompanyState(
        status: CompanyStatus.ready,
        draft: draft,
        approval: state.approval,
      ),
    );
  }

  Future<void> load() async {
    if (isClosed || busy) return;
    final generation = ++_generation;
    final previous = state;
    emit(
      CompanyState(
        status: CompanyStatus.loading,
        draft: previous.draft,
        approval: previous.approval,
      ),
    );
    try {
      final saved = await repository.load();
      if (isClosed || generation != _generation) return;
      emit(
        CompanyState(
          status: CompanyStatus.ready,
          draft: saved?.draft ?? previous.draft,
          approval: saved?.approval,
        ),
      );
    } catch (_) {
      if (isClosed || generation != _generation) return;
      emit(
        CompanyState(
          status: CompanyStatus.failure,
          draft: previous.draft,
          approval: previous.approval,
          message: 'Unable to load your company. Please retry.',
        ),
      );
    }
  }

  Future<void> save() async {
    if (isClosed || busy) return;
    final draft = state.draft;
    final approval = state.approval;
    final errors = draft.validate();
    if (errors.isNotEmpty) {
      emit(
        CompanyState(
          status: CompanyStatus.ready,
          draft: draft,
          approval: approval,
          errors: errors,
        ),
      );
      return;
    }
    final generation = ++_generation;
    emit(
      CompanyState(
        status: CompanyStatus.saving,
        draft: draft,
        approval: approval,
      ),
    );
    try {
      final saved = await repository.save(draft);
      if (isClosed || generation != _generation) return;
      if (saved.approval != CompanyApproval.pending) {
        throw const CompanyFailure('Unexpected approval state');
      }
      emit(
        CompanyState(
          status: CompanyStatus.saved,
          draft: saved.draft,
          approval: saved.approval,
          message: 'Company submitted for review.',
        ),
      );
    } catch (_) {
      if (isClosed || generation != _generation) return;
      emit(
        CompanyState(
          status: CompanyStatus.failure,
          draft: draft,
          approval: approval,
          message: 'Unable to save your company. Your edits are still here.',
        ),
      );
    }
  }

  void reset() {
    if (isClosed) return;
    ++_generation;
    emit(
      const CompanyState(
        status: CompanyStatus.initial,
        draft: CompanyDraft(name: ''),
      ),
    );
  }
}
