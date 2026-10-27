import '../../company/domain/company.dart';

enum ReviewDecision { approved, rejected }

class ReviewFailure implements Exception {
  const ReviewFailure(this.message, {this.reloadRequired = false});
  final String message;
  final bool reloadRequired;
}

bool validReviewText(String value, int maximum) =>
    value.isNotEmpty &&
    value.length <= maximum &&
    value.trim().isNotEmpty &&
    !value.runes.any((r) => r < 32 || r == 127);

class ReviewSubmission {
  const ReviewSubmission(this.company);
  final SavedCompany company;

  factory ReviewSubmission.fromJson(Map<String, dynamic> json) {
    final owner = json['owner_uid'];
    if (owner is! String || !validReviewText(owner, 128)) {
      throw const FormatException('Invalid submission owner');
    }
    final company = SavedCompany.fromJson(json, expectedOwnerUid: owner);
    if (company.approval != CompanyApproval.pending) {
      throw const FormatException('Submission is not pending');
    }
    return ReviewSubmission(company);
  }

  Map<String, Object> command(ReviewDecision decision, String reason) {
    final clean = reason.trim();
    if (!validReviewText(clean, 500) || clean.length < 3) {
      throw const ReviewFailure('Enter a review reason of 3–500 characters.');
    }
    return {
      'target_uid': company.ownerUid,
      'decision': decision.name,
      'expected_company_updated_at': company.updatedAt.toIso8601String(),
      'reason': clean,
    };
  }
}

class ReviewPage {
  ReviewPage(List<ReviewSubmission> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<ReviewSubmission> items;
  final String? nextCursor;

  factory ReviewPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final cursor = json['next_cursor'];
    if (raw is! List ||
        raw.length > 10 ||
        (cursor != null &&
            (cursor is! String || !validReviewText(cursor, 128)))) {
      throw const FormatException('Invalid review page');
    }
    final items = raw.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid submission');
      }
      return ReviewSubmission.fromJson(item);
    }).toList();
    if (items.map((item) => item.company.ownerUid).toSet().length !=
        items.length) {
      throw const FormatException('Duplicate submissions');
    }
    return ReviewPage(items, cursor as String?);
  }
}

abstract interface class RecruiterReviewRepository {
  Future<ReviewPage> load({String? cursor});
  Future<void> review(
    ReviewSubmission submission,
    ReviewDecision decision,
    String reason,
  );
}
