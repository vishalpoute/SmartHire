import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/profile/domain/profile.dart';

void main() {
  Map<String, Object?> response() => {
    'uid': 'owner',
    'updated_at': '2026-10-17T10:00:00+05:30',
    'display_name': 'Ada',
    'headline': '',
    'location': '',
    'skills': ['Dart'],
    'role': 'admin',
  };

  test('write payload contains only editable trimmed fields', () {
    final profile = SavedProfile.fromJson(response());
    expect(
      profile.draft.toJson().keys,
      unorderedEquals(['display_name', 'headline', 'location', 'skills']),
    );
    expect(ProfileDraft(displayName: ' Ada ', skills: [' Dart ']).toJson(), {
      'display_name': 'Ada',
      'headline': '',
      'location': '',
      'skills': ['Dart'],
    });
    expect(profile.updatedAt, DateTime.utc(2026, 10, 17, 4, 30));
  });

  test(
    'validation covers field limits, blank skills and total skill count',
    () {
      expect(
        ProfileDraft(
          displayName: ' ',
          headline: 'x' * 121,
          location: 'x' * 81,
          skills: [' '],
        ).validate().keys,
        unorderedEquals(['display_name', 'headline', 'location', 'skills']),
      );
      expect(
        ProfileDraft(
          displayName: 'Ada',
          skills: List.filled(31, 'Dart'),
        ).validate(),
        contains('skills'),
      );
      expect(
        ProfileDraft(displayName: 'Ada', skills: ['x' * 41]).validate(),
        contains('skills'),
      );
      expect(ProfileDraft(displayName: '😀' * 80).validate(), isEmpty);
    },
  );

  test('draft snapshots input skills and cannot be mutated', () {
    final skills = ['Dart'];
    final draft = ProfileDraft(displayName: 'Ada', skills: skills);
    skills.clear();
    expect(draft.skills, ['Dart']);
    expect(() => draft.skills.add('Python'), throwsUnsupportedError);
  });

  test('malformed server values fail closed', () {
    for (final patch in <Map<String, Object?>>[
      {'uid': ''},
      {'updated_at': 'bad'},
      {'updated_at': '2026-10-17T10:00:00'},
      {
        'skills': [1],
      },
      {'display_name': null},
      {'display_name': 'x'},
    ]) {
      expect(
        () => SavedProfile.fromJson({...response(), ...patch}),
        throwsFormatException,
      );
    }
  });
}
