# Private resume processing

## Implemented foundation

Offline text extraction supports PDF and DOCX with explicit parsed/unscored outcomes and parser version `text-v1-pypdf6.21.2-docx1.2.0`. There is no OCR, model inference or automatic score. Encrypted PDFs, empty/image-only documents, invalid signatures, excessive pages/text, unsafe archives and XML document types are rejected with safe machine codes. No private document or library diagnostic is logged.

Limits are 5 MiB compressed input, 20 PDF pages, 100,000 extracted characters, 200 ZIP entries, 20 MiB total uncompressed DOCX content, 4 MiB per entry and a maximum 100:1 compression ratio. Duplicate/path-traversal/encrypted/macro members are rejected. XML is checked with entity expansion, external DTD loading and network access disabled, including UTF-16 documents. Extraction runs in a fresh isolated Python subprocess with a 15-second wall timeout and no inherited cloud credentials. Linux also applies 8 CPU seconds and a 512 MiB address-space limit. These process controls are not a filesystem or network sandbox; deployment must retain the library/input checks. Windows tests exercise timeout and input boundaries; they do not prove Linux resource enforcement.

Private storage uses the existing Antideploy account's free S3-compatible bucket. Firebase remains responsible for authentication and Firestore metadata; FastAPI remains the authorization boundary. Credentials stay outside Git/frontend files and must be installed in the existing Render API environment before enabling integration. There is no paid parsing service.

Object paths are server-derived from a hashed verified owner UID and a generated resume ID. Upload tickets expire after 60 seconds, sign the exact content length/type/hash metadata, and require `If-None-Match: *`. A live nonpersonal check verified incorrect length was refused with 403, overwriting was refused with 412, checksum readback succeeded, anonymous reads were refused with 403, and cleanup succeeded. Never log a signed URL. The server independently checks actual byte count and SHA-256 before processing; metadata alone is insufficient.

## Integration contract for the next implementation

Resume metadata and durable queued/processing leases will live in Firestore. Each source upload is immutable; corrections to confirmed skills have a separate optimistic version. Every owner operation must derive UID from the verified session, recheck active-account state transactionally, and use identical unavailable responses for missing/foreign IDs. Storage keys, raw extraction and lease tokens must stay out of public/list responses. Application snapshots will pin source and confirmed-skill versions.

An upload request creates private metadata and a short-lived upload ticket; finalization queues parsing. Workers must use persisted leases, bounded attempts and recovery after restart. Failed parsing remains explicitly unscored and cannot silently create confirmed skills or a match score. The owner must confirm or correct skill suggestions before matching. No resume upload, processing or confirmation endpoint is enabled by this foundation alone.

Pending uploads should expire after 15 minutes, with durable cleanup. Owner-requested deletion must remove the private original and extracted text; cleanup failures must remain visible/retriable rather than claiming deletion. Application-retention and recruiter access contracts must be completed before those features expose resume content. Raw resumes must never appear in public job responses.

## Dependencies and validation

The user approved the free dependencies on 28 October. Primary metadata/licenses were checked for [pypdf (BSD-3-Clause)](https://github.com/py-pdf/pypdf/blob/main/LICENSE), [python-docx (MIT)](https://github.com/python-openxml/python-docx/blob/master/LICENSE) and [boto3 (Apache-2.0)](https://github.com/boto/boto3/blob/develop/LICENSE). Preserve upstream notices distributed with these packages. Direct and transitive versions are pinned in the API lock file; no applicable non-withdrawn GitHub advisories were returned for the nine new pins at the check time.

All 282 API tests pass, including 26 parser/storage checks; Ruff, Bandit and dependency consistency checks pass. This is boundary/fixture validation, not parser-quality acceptance. A consented annotated evaluation set and agreed numerical release thresholds remain required. Authenticated owner/two-account HTTP acceptance, durable worker integration and UI acceptance remain unverified.
