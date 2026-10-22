import 'package:flutter_test/flutter_test.dart';

import 'package:smarthire/features/company/domain/company.dart';

void main() {
  Map<String, Object?> receipt() => {
    'owner_uid': 'owner',
    'approval_status': 'pending',
    'updated_at': '2026-10-21T12:00:00+05:30',
    'name': 'Company',
    'description': '',
    'location': '',
    'website': '',
  };

  test(
    'server company receipt preserves approval and normalizes timestamp',
    () {
      for (final status in CompanyApproval.values) {
        final json = receipt()..['approval_status'] = status.name;
        final company = SavedCompany.fromJson(json, expectedOwnerUid: 'owner');
        expect(company.approval, status);
        expect(company.updatedAt, DateTime.utc(2026, 10, 21, 6, 30));
        expect(company.draft.toJson(), isNot(contains('approval_status')));
      }
    },
  );

  test(
    'server company receipt rejects foreign ownership and malformed data',
    () {
      for (final entry in <String, Object?>{
        'owner_uid': 'other',
        'approval_status': 'admin',
        'updated_at': '2026-10-21T12:00:00',
        'name': 42,
        'website': 'http://example.com',
      }.entries) {
        final json = receipt()..[entry.key] = entry.value;
        expect(
          () => SavedCompany.fromJson(json, expectedOwnerUid: 'owner'),
          throwsFormatException,
        );
      }
    },
  );

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
