import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/public_jobs_repository.dart';

class PublicJobsState {
  PublicJobsState({
    List<PublishedJob> items = const [],
    this.nextCursor,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  }) : items = List.unmodifiable(items);
  final List<PublishedJob> items;
  final String? nextCursor;
  final bool loading;
  final bool loadingMore;
  final String? error;
}

class PublicJobsCubit extends Cubit<PublicJobsState> {
  PublicJobsCubit(this.repository) : super(PublicJobsState());
  final PublicJobsRepository repository;
  int _generation = 0;

  Future<void> refresh() async {
    final generation = ++_generation;
    emit(PublicJobsState(loading: true));
    try {
      final page = await repository.page();
      if (!isClosed && generation == _generation) {
        emit(PublicJobsState(items: page.items, nextCursor: page.nextCursor));
      }
    } catch (_) {
      if (!isClosed && generation == _generation) {
        emit(PublicJobsState(error: 'Could not load jobs. Please retry.'));
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (state.loading || state.loadingMore || cursor == null) return;
    final generation = _generation;
    final previous = state.items;
    emit(
      PublicJobsState(items: previous, nextCursor: cursor, loadingMore: true),
    );
    try {
      final page = await repository.page(cursor: cursor);
      if (!isClosed && generation == _generation) {
        final items = {
          for (final job in previous) job.id: job,
          for (final job in page.items) job.id: job,
        };
        emit(
          PublicJobsState(
            items: items.values.toList(),
            nextCursor: page.nextCursor,
          ),
        );
      }
    } catch (_) {
      if (!isClosed && generation == _generation) {
        emit(
          PublicJobsState(
            items: previous,
            nextCursor: cursor,
            error: 'Could not load more jobs. Please retry.',
          ),
        );
      }
    }
  }
}
