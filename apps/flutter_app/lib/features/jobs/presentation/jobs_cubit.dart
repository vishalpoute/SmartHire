import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/job.dart';
import '../domain/job_repository.dart';

enum JobSort { newest, title }

enum JobsStatus { initial, loading, ready, failure }

class JobsState {
  JobsState({
    this.status = JobsStatus.initial,
    List<Job> jobs = const [],
    this.query = '',
    this.mode,
    Set<String> savedIds = const {},
    this.savedOnly = false,
    this.sort = JobSort.newest,
  }) : jobs = List.unmodifiable(jobs),
       savedIds = Set.unmodifiable(savedIds);
  final JobsStatus status;
  final List<Job> jobs;
  final String query;
  final WorkMode? mode;
  final Set<String> savedIds;
  final bool savedOnly;
  final JobSort sort;

  List<Job> get visibleJobs {
    final term = query.trim().toLowerCase();
    final result = jobs
        .where(
          (job) =>
              (mode == null || job.mode == mode) &&
              (!savedOnly || savedIds.contains(job.id)) &&
              '${job.title} ${job.company} ${job.location} ${job.skills.join(' ')}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList(growable: false);
    result.sort((a, b) {
      final comparison = sort == JobSort.newest
          ? a.postedDaysAgo.compareTo(b.postedDaysAgo)
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return comparison == 0 ? a.id.compareTo(b.id) : comparison;
    });
    return result;
  }
}

class JobsCubit extends Cubit<JobsState> {
  JobsCubit(this._repository) : super(JobsState());
  final JobRepository _repository;

  Future<void> load() async {
    emit(_next(status: JobsStatus.loading));
    try {
      final jobs = await _repository.fetchPublishedJobs();
      if (!isClosed) emit(_next(status: JobsStatus.ready, jobs: jobs));
    } catch (_) {
      if (!isClosed) emit(_next(status: JobsStatus.failure));
    }
  }

  void search(String query) => emit(_next(query: query));
  void filter(WorkMode? mode) => emit(_next(mode: mode, replaceMode: true));
  void sortBy(JobSort sort) => emit(_next(sort: sort));
  void resetFilters() => emit(_next(query: '', replaceMode: true));
  void showSaved(bool enabled) => emit(_next(savedOnly: enabled));
  void toggleSaved(String id) {
    final ids = {...state.savedIds};
    if (!ids.add(id)) ids.remove(id);
    emit(_next(savedIds: ids));
  }

  JobsState _next({
    JobsStatus? status,
    List<Job>? jobs,
    String? query,
    WorkMode? mode,
    bool replaceMode = false,
    Set<String>? savedIds,
    bool? savedOnly,
    JobSort? sort,
  }) => JobsState(
    status: status ?? state.status,
    jobs: jobs ?? state.jobs,
    query: query ?? state.query,
    mode: replaceMode ? mode : state.mode,
    savedIds: savedIds ?? state.savedIds,
    savedOnly: savedOnly ?? state.savedOnly,
    sort: sort ?? state.sort,
  );
}
