class RecruiterJobFailure implements Exception {
  const RecruiterJobFailure(this.message, {this.accessDenied = false});
  final String message;
  final bool accessDenied;
}

bool validJobId(String value) =>
    value.length == 32 && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

class RecruiterJobFields {
  RecruiterJobFields({
    required this.title,
    this.description = '',
    this.location = '',
    this.workMode = 'onsite',
    this.employmentType = 'full_time',
    List<String> requiredSkills = const [],
    List<String> preferredSkills = const [],
  }) : requiredSkills = List.unmodifiable(requiredSkills),
       preferredSkills = List.unmodifiable(preferredSkills);
  final String title, description, location, workMode, employmentType;
  final List<String> requiredSkills, preferredSkills;
  static const workModes = ['remote', 'hybrid', 'onsite'];
  static const employmentTypes = [
    'full_time',
    'part_time',
    'contract',
    'internship',
  ];

  String? validate({bool publish = false}) {
    if (title.trim().length < 2 ||
        title.trim().length > 120 ||
        description.trim().length > 12000 ||
        location.trim().length > 80 ||
        !workModes.contains(workMode) ||
        !employmentTypes.contains(employmentType)) {
      return 'Check the title (2–120 characters), description and location.';
    }
    for (final skills in [requiredSkills, preferredSkills]) {
      if (skills.length > 30 ||
          skills.any((s) => s.trim().isEmpty || s.trim().length > 40)) {
        return 'Use up to 30 skills per list, each 1–40 characters.';
      }
    }
    if (publish) {
      final required = requiredSkills
          .map((s) => s.trim().toLowerCase())
          .toSet();
      if (description.trim().length < 20 ||
          required.isEmpty ||
          (workMode != 'remote' && location.trim().isEmpty) ||
          preferredSkills.any(
            (s) => required.contains(s.trim().toLowerCase()),
          )) {
        return 'Publishing requires a description of at least 20 characters, required skills, '
            'a location for onsite/hybrid work, and separate required/preferred skills.';
      }
    }
    return null;
  }

  Map<String, Object> toJson() => {
    'title': title.trim(),
    'description': description.trim(),
    'location': location.trim(),
    'work_mode': workMode,
    'employment_type': employmentType,
    'required_skills': requiredSkills.map((s) => s.trim()).toList(),
    'preferred_skills': preferredSkills.map((s) => s.trim()).toList(),
  };
}

class RecruiterJob {
  const RecruiterJob({
    required this.id,
    required this.version,
    required this.status,
    required this.fields,
  });
  final String id, status;
  final int version;
  final RecruiterJobFields fields;

  factory RecruiterJob.fromJson(
    Map<String, dynamic> json,
    String owner, {
    String? expectedId,
  }) {
    String field(String key) {
      final value = json[key];
      if (value is! String) throw const FormatException('Invalid owned job');
      return value;
    }

    List<String> skills(String key) {
      final value = json[key];
      if (value is! List || value.any((item) => item is! String)) {
        throw const FormatException('Invalid job skills');
      }
      return value.cast<String>();
    }

    final id = field('id');
    final status = field('status');
    final version = json['version'];
    if (!validJobId(id) ||
        (expectedId != null && expectedId != id) ||
        owner.isEmpty ||
        field('recruiter_uid') != owner ||
        field('company_owner_uid') != owner ||
        !['draft', 'published', 'closed', 'suspended'].contains(status) ||
        version is! int ||
        version < 1 ||
        version > 2147483647) {
      throw const FormatException('Invalid owned job identity or lifecycle');
    }
    for (final key in ['created_at', 'updated_at']) {
      final raw = field(key);
      if (DateTime.tryParse(raw) == null ||
          !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
        throw const FormatException('Invalid job timestamp');
      }
    }
    final fields = RecruiterJobFields(
      title: field('title'),
      description: field('description'),
      location: field('location'),
      workMode: field('work_mode'),
      employmentType: field('employment_type'),
      requiredSkills: skills('required_skills'),
      preferredSkills: skills('preferred_skills'),
    );
    if (fields.validate() != null) {
      throw const FormatException('Invalid job fields');
    }
    return RecruiterJob(
      id: id,
      version: version,
      status: status,
      fields: fields,
    );
  }
}

abstract interface class RecruiterJobsRepository {
  Future<OwnedJobsPage> list({String? cursor});
  Future<RecruiterJob> load(String id);
  Future<RecruiterJob> save(
    RecruiterJobFields fields, {
    RecruiterJob? previous,
  });
  Future<void> transition(RecruiterJob job, {required bool publish});
}

class OwnedJobsPage {
  OwnedJobsPage(List<RecruiterJob> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<RecruiterJob> items;
  final String? nextCursor;
  factory OwnedJobsPage.fromJson(Map<String, dynamic> json, String owner) {
    final raw = json['items'];
    final cursor = json['next_cursor'];
    if (raw is! List ||
        raw.length > 10 ||
        (cursor != null && (cursor is! String || !validJobId(cursor)))) {
      throw const FormatException('Invalid owned job page');
    }
    final items = raw.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid owned job');
      }
      return RecruiterJob.fromJson(item, owner);
    }).toList();
    if (items.map((job) => job.id).toSet().length != items.length) {
      throw const FormatException('Duplicate owned jobs');
    }
    return OwnedJobsPage(items, cursor as String?);
  }
}
