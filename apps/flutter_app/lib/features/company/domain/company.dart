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
