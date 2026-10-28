enum PublishedWorkMode { remote, hybrid, onsite }

enum EmploymentType { fullTime, partTime, contract, internship }

class PublishedJob {
  PublishedJob({
    required this.id,
    required this.title,
    required this.company,
    required this.description,
    required this.location,
    required this.workMode,
    required this.employmentType,
    required List<String> requiredSkills,
    required List<String> preferredSkills,
    required this.publishedAt,
  }) : requiredSkills = List.unmodifiable(requiredSkills),
       preferredSkills = List.unmodifiable(preferredSkills);

  final String id;
  final String title;
  final String company;
  final String description;
  final String location;
  final PublishedWorkMode workMode;
  final EmploymentType employmentType;
  final List<String> requiredSkills;
  final List<String> preferredSkills;
  final DateTime publishedAt;
}

class PublicJobsPage {
  PublicJobsPage({required List<PublishedJob> items, this.nextCursor})
    : items = List.unmodifiable(items);
  final List<PublishedJob> items;
  final String? nextCursor;
}

class PublicJobsFailure implements Exception {
  const PublicJobsFailure(this.message);
  final String message;
}

abstract interface class PublicJobsRepository {
  Future<PublicJobsPage> page({
    int pageSize = 10,
    String? cursor,
    String search = '',
    String? workMode,
    String? employmentType,
  });
  Future<PublishedJob?> detail(String id);
}
