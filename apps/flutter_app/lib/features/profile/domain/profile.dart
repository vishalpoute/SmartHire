/// Editable profile fields. Identity and permissions never belong in a write body.
class ProfileDraft {
  ProfileDraft({
    required this.displayName,
    this.headline = '',
    this.location = '',
    List<String> skills = const [],
  }) : skills = List.unmodifiable(skills);

  final String displayName;
  final String headline;
  final String location;
  final List<String> skills;

  /// Field errors for the editor; the server remains authoritative.
  Map<String, String> validate() {
    final errors = <String, String>{};
    final nameLength = displayName.trim().runes.length;
    if (nameLength < 2 || nameLength > 80) {
      errors['display_name'] = 'Use between 2 and 80 characters.';
    }
    if (headline.trim().runes.length > 120) {
      errors['headline'] = 'Use at most 120 characters.';
    }
    if (location.trim().runes.length > 80) {
      errors['location'] = 'Use at most 80 characters.';
    }
    if (skills.length > 30 ||
        skills.any(
          (skill) => skill.trim().isEmpty || skill.trim().runes.length > 40,
        )) {
      errors['skills'] =
          'Add up to 30 skills, each between 1 and 40 characters.';
    }
    return Map.unmodifiable(errors);
  }

  Map<String, Object> toJson() => {
    'display_name': displayName.trim(),
    'headline': headline.trim(),
    'location': location.trim(),
    'skills': skills.map((skill) => skill.trim()).toList(),
  };
}

/// A server response, kept separate from the editable payload.
class SavedProfile {
  const SavedProfile({
    required this.uid,
    required this.updatedAt,
    required this.draft,
  });

  final String uid;
  final DateTime updatedAt;
  final ProfileDraft draft;

  factory SavedProfile.fromJson(Map<String, Object?> json) {
    String field(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('Invalid profile field: $key');
      }
      return value;
    }

    final uid = field('uid');
    final timestamp = field('updated_at');
    final date = DateTime.tryParse(timestamp);
    final skills = json['skills'];
    if (uid.isEmpty ||
        date == null ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(timestamp) ||
        skills is! List ||
        skills.any((value) => value is! String)) {
      throw const FormatException('Invalid saved profile');
    }
    final draft = ProfileDraft(
      displayName: field('display_name'),
      headline: field('headline'),
      location: field('location'),
      skills: skills.cast<String>(),
    );
    if (draft.validate().isNotEmpty) {
      throw const FormatException('Invalid saved profile fields');
    }
    return SavedProfile(uid: uid, updatedAt: date.toUtc(), draft: draft);
  }
}
