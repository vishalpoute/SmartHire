enum WorkMode { remote, hybrid, onsite }

extension WorkModeLabel on WorkMode {
  String get label => switch (this) {
    WorkMode.remote => 'Remote',
    WorkMode.hybrid => 'Hybrid',
    WorkMode.onsite => 'On-site',
  };
}

class Job {
  const Job({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.mode,
    required this.salary,
    required this.skills,
    required this.description,
    required this.postedDaysAgo,
  });
  final String id;
  final String title;
  final String company;
  final String location;
  final WorkMode mode;
  final String salary;
  final List<String> skills;
  final String description;
  final int postedDaysAgo;
}
