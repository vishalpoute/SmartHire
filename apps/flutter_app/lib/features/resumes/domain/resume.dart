import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const maxResumeBytes = 5 * 1024 * 1024;
bool resumeHex(String value, int length) =>
    value.length == length && RegExp(r'^[a-f0-9]+$').hasMatch(value);

class ResumeFailure implements Exception {
  const ResumeFailure(
    this.message, {
    this.accessDenied = false,
    this.reloadRequired = false,
  });
  final String message;
  final bool accessDenied, reloadRequired;
}

enum ResumeStatus {
  uploading,
  queued,
  processing,
  parsed,
  unscored,
  confirmed,
  deleting,
}

class PickedResume {
  PickedResume({
    required this.name,
    required this.extension,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (!['pdf', 'docx'].contains(extension) ||
        bytes.isEmpty ||
        bytes.length > maxResumeBytes) {
      throw const ResumeFailure('Choose a PDF or DOCX up to 5 MB.');
    }
  }
  final String name, extension;
  final Uint8List bytes;
  late final String digest = sha256.convert(bytes).toString();
}

String newResumeUploadId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String resumeIdFor(String owner, String nonce) => sha256
    .convert(utf8.encode('$owner\u0000$nonce'))
    .toString()
    .substring(0, 32);
String resumeOwnerHash(String owner) =>
    sha256.convert(utf8.encode(owner)).toString();

class ResumeRecord {
  ResumeRecord({
    required this.id,
    required this.version,
    required this.revision,
    required this.extension,
    required this.size,
    required this.digest,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required List<String> extractedSkills,
    required List<String>? confirmedSkills,
    required this.skillsVersion,
    this.parserVersion,
    this.taxonomyVersion,
    this.errorCode,
  }) : extractedSkills = List.unmodifiable(extractedSkills),
       confirmedSkills = confirmedSkills == null
           ? null
           : List.unmodifiable(confirmedSkills);
  final String id, extension, digest;
  final int version, revision, size, skillsVersion;
  final ResumeStatus status;
  final DateTime createdAt, updatedAt;
  final List<String> extractedSkills;
  final List<String>? confirmedSkills;
  final String? parserVersion, taxonomyVersion, errorCode;

  factory ResumeRecord.fromJson(
    Map<String, dynamic> json, {
    String? expectedId,
  }) {
    Never invalid() => throw const FormatException('Invalid resume response');
    String string(String key) =>
        json[key] is String ? json[key] as String : invalid();
    int number(String key, int min, int max) {
      final value = json[key];
      if (value is! int || value < min || value > max) invalid();
      return value;
    }

    String? optional(String key) {
      final value = json[key];
      if (value != null && (value is! String || value.length > 120)) invalid();
      return value as String?;
    }

    List<String> skills(String key) {
      final value = json[key];
      if (value is! List ||
          value.length > 30 ||
          value.any(
            (s) =>
                s is! String ||
                s.trim().isEmpty ||
                s.length > 40 ||
                s.runes.any((r) => r < 32 || r == 127),
          )) {
        invalid();
      }
      return (value).cast<String>();
    }

    DateTime date(String key) {
      final raw = string(key);
      final parsed = DateTime.tryParse(raw);
      if (parsed == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
        invalid();
      }
      return parsed.toUtc();
    }

    final id = string('id'),
        digest = string('sha256'),
        extension = string('extension');
    if (!resumeHex(id, 32) ||
        (expectedId != null && id != expectedId) ||
        !resumeHex(digest, 64) ||
        !['pdf', 'docx'].contains(extension)) {
      invalid();
    }
    final statuses = ResumeStatus.values
        .where((s) => s.name == json['parse_status'])
        .toList();
    if (statuses.length != 1) invalid();
    final confirmed = json['confirmed_skills'] == null
        ? null
        : skills('confirmed_skills');
    final skillVersion = number('skills_version', 0, 2147483647);
    final parser = optional('parser_version');
    if (statuses.single == ResumeStatus.confirmed &&
        (confirmed == null || skillVersion < 1 || parser == null)) {
      invalid();
    }
    final error = optional('error_code');
    if (error != null &&
        !const {
          'unsupported_type',
          'size_limit',
          'invalid_document',
          'encrypted_pdf',
          'empty_text',
          'resource_limit',
          'storage_unavailable',
          'object_mismatch',
          'invalid_object',
          'account_inactive',
        }.contains(error)) {
      invalid();
    }
    return ResumeRecord(
      id: id,
      version: number('version', 1, 2147483647),
      revision: number('revision', 1, 2147483647),
      extension: extension,
      size: number('size', 1, maxResumeBytes),
      digest: digest,
      status: statuses.single,
      createdAt: date('created_at'),
      updatedAt: date('updated_at'),
      extractedSkills: skills('extracted_skills'),
      confirmedSkills: confirmed,
      skillsVersion: skillVersion,
      parserVersion: parser,
      taxonomyVersion: optional('taxonomy_version'),
      errorCode: error,
    );
  }
}

class ResumesPage {
  ResumesPage(List<ResumeRecord> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<ResumeRecord> items;
  final String? nextCursor;
  factory ResumesPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'], cursor = json['next_cursor'];
    if (raw is! List ||
        raw.length > 10 ||
        (cursor != null && (cursor is! String || !resumeHex(cursor, 32)))) {
      throw const FormatException('Invalid resume page');
    }
    final items = raw.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid resume');
      }
      return ResumeRecord.fromJson(item);
    }).toList();
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Duplicate resumes');
    }
    return ResumesPage(items, cursor as String?);
  }
}

abstract interface class ResumeRepository {
  Future<ResumesPage> list({String? cursor});
  Future<ResumeRecord> load(String id);
  Future<ResumeRecord> upload(
    PickedResume file,
    String uploadId,
    void Function(int, int) progress,
  );
  Future<ResumeRecord> confirm(ResumeRecord record, List<String> skills);
  Future<ResumeRecord> retry(ResumeRecord record);
  Future<bool> delete(ResumeRecord record);
}

String resumeErrorMessage(String? code) => switch (code) {
  'empty_text' => 'No readable text was found. Upload a text PDF or DOCX; scanned images are not supported.',
  'encrypted_pdf' => 'Upload a PDF without password protection.',
  'size_limit' => 'The document exceeds a processing limit. Try a smaller file or a PDF with fewer pages.',
  'invalid_document' ||
  'object_mismatch' ||
  'invalid_object' ||
  'unsupported_type' =>
    'The document could not be read safely. Choose a new PDF or DOCX.',
  'resource_limit' =>
    'Processing could not finish within its limits. Try a smaller document.',
  'storage_unavailable' =>
    'The private file is temporarily unavailable. You can retry processing.',
  'account_inactive' =>
    'Your account cannot process this document. Check your account status.',
  _ => 'Processing has not completed. Refresh to check its status.',
};
