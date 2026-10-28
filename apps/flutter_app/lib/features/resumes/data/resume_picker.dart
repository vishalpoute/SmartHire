import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/resume.dart';

Future<PickedResume?> pickPrivateResume() async {
  try {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
    );
    if (file == null) return null;
    final size = await file.length();
    final extension = file.extension?.toLowerCase();
    if (size == null ||
        size < 1 ||
        size > maxResumeBytes ||
        !['pdf', 'docx'].contains(extension)) {
      throw const ResumeFailure('Choose a PDF or DOCX up to 5 MB.');
    }
    final bytes = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in file.readAsByteStream()) {
      total += chunk.length;
      if (total > maxResumeBytes) {
        throw const ResumeFailure('The selected file is too large.');
      }
      bytes.add(chunk);
    }
    if (total != size) {
      throw const ResumeFailure(
        'The file changed while reading. Choose it again.',
      );
    }
    return PickedResume(
      name: file.name,
      extension: extension!,
      bytes: bytes.takeBytes(),
    );
  } on ResumeFailure {
    rethrow;
  } catch (_) {
    throw const ResumeFailure(
      'Unable to read the selected document. Please choose it again.',
    );
  }
}
