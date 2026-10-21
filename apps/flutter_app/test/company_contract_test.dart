import 'package:flutter_test/flutter_test.dart';

import 'package:smarthire/features/company/domain/company.dart';

void main() {
  test('company writes normalize only editable fields', () {
    const draft = CompanyDraft(
      name: ' Company ',
      website: ' https://example.com ',
    );
    expect(draft.validate(), isEmpty);
    expect(draft.toJson(), {
      'name': 'Company',
      'description': '',
      'location': '',
      'website': 'https://example.com',
    });
  });

  test(
    'company website rejects credentials, insecure URLs and invalid ports',
    () {
      for (final website in [
        'http://example.com',
        'https://user:pass@example.com',
        'https://example.com:0',
        'https://example.com:99999',
        'https://example.com/a b',
        'https://',
      ]) {
        expect(
          CompanyDraft(name: 'Company', website: website).validate(),
          contains('website'),
          reason: website,
        );
      }
    },
  );

  test('company bounds count Unicode characters and enforce server limits', () {
    expect(
      CompanyDraft(
        name: 'A',
        description: 'a' * 2001,
        location: 'a' * 81,
      ).validate().keys,
      containsAll(['name', 'description', 'location']),
    );
    expect(CompanyDraft(name: '😀' * 120).validate(), isEmpty);
    expect(CompanyDraft(name: '😀' * 121).validate(), contains('name'));
  });
}
