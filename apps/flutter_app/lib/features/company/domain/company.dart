enum CompanyApproval { pending, approved, rejected }

/// A server receipt, never used as an editable write body.
class SavedCompany {
  const SavedCompany({
    required this.ownerUid,
    required this.approval,
    required this.updatedAt,
    required this.draft,
  });

  final String ownerUid;
  final CompanyApproval approval;
  final DateTime updatedAt;
  final CompanyDraft draft;

  factory SavedCompany.fromJson(
    Map<String, Object?> json, {
    required String expectedOwnerUid,
  }) {
    String field(String key) {
      final value = json[key];
      if (value is! String) {
        throw const FormatException('Invalid company response');
      }
      return value;
    }

    final owner = field('owner_uid');
    final timestamp = field('updated_at');
    final date = DateTime.tryParse(timestamp);
    final status = field('approval_status');
    final approvals = CompanyApproval.values.where(
      (item) => item.name == status,
    );
    final draft = CompanyDraft(
      name: field('name'),
      description: field('description'),
      location: field('location'),
      website: field('website'),
    );
    if (owner.isEmpty ||
        owner != expectedOwnerUid ||
        date == null ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(timestamp) ||
        approvals.length != 1 ||
        draft.validate().isNotEmpty) {
      throw const FormatException('Invalid company response');
    }
    return SavedCompany(
      ownerUid: owner,
      approval: approvals.single,
      updatedAt: date.toUtc(),
      draft: draft,
    );
  }
}

/// Editable company data. Identity and approval never belong in write bodies.
class CompanyDraft {
  const CompanyDraft({
    required this.name,
    this.description = '',
    this.location = '',
    this.website = '',
  });

  final String name;
  final String description;
  final String location;
  final String website;

  Map<String, String> validate() {
    final errors = <String, String>{};
    final length = name.trim().runes.length;
    if (length < 2 || length > 120) {
      errors['name'] = 'Use between 2 and 120 characters.';
    }
    if (description.trim().runes.length > 2000) {
      errors['description'] = 'Use at most 2000 characters.';
    }
    if (location.trim().runes.length > 80) {
      errors['location'] = 'Use at most 80 characters.';
    }
    final value = website.trim();
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      var valid =
          uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          !RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value);
      try {
        valid = valid && uri.port > 0 && uri.port <= 65535;
      } on FormatException {
        valid = false;
      }
      if (!valid || value.runes.length > 500) {
        errors['website'] = 'Use an HTTPS website without credentials.';
      }
    }
    return Map.unmodifiable(errors);
  }

  Map<String, Object> toJson() => {
    'name': name.trim(),
    'description': description.trim(),
    'location': location.trim(),
    'website': website.trim(),
  };
}
