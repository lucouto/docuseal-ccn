# Implementation Plan: Documents in, by any route

**Branch**: `ccn` | **Date**: 2026-09-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-documents-by-any-route/spec.md`

## Summary

Add three ingestion capabilities to the fork without touching the signing/result/audit code: (1) a text-tag
detector on pdfium text nodes with redaction, wired into the single place every PDF passes through
(`Templates::CreateAttachments#handle_pdf_or_image`); (2) a Gotenberg client that turns DOCX/ODT/RTF/XLSX and
HTML into PDF before that same place; (3) eight API operations implemented to `docs/openapi.json` as new
controllers that reuse upstream's template/submission services, plus an HTML field-tag pre-processor that
turns `<x-field>` elements into invisible text tags so one detector serves PDF, DOCX and HTML.

## Technical Context

**Language/Version**: Ruby 4.0.5 / Rails 8.1 (upstream 3.2.4), Vue 3 front end untouched in this feature

**Primary Dependencies**: `pdfium` FFI binding (`lib/pdfium.rb`: `Page#text_nodes`, `Page#redact`, `Document#save`, `Document.create`/`import_pages`), `faraday` 2.x (already bundled) for Gotenberg, `nokogiri` (already bundled) for HTML pre-processing, `hexapdf` (bundled) to build PDF fixtures in specs, `webmock` (bundled) to stub Gotenberg in specs

**Storage**: PostgreSQL (unchanged schema — no migration), ActiveStorage blobs on the `/data` volume; document metadata `pdf.fields` as upstream

**Testing**: RSpec request specs (`spec/requests/`), lib specs (`spec/lib/`), contract spec extended to 22 operations; CI runs on `ruby:4.0.5-alpine` with pdfium and chromium but **no LibreOffice** → Gotenberg is stubbed with WebMock in CI and exercised for real on staging by the gate scripts

**Target Platform**: Linux/amd64 container on Coolify, Gotenberg 8.37.0 sidecar (`GOTENBERG_URL`)

**Project Type**: Rails monolith (web service + API)

**Performance Goals**: tag detection O(characters) per page (< 100 ms for a 15-page document); DOCX→PDF 1–5 s typical, bounded by the sidecar's 90 s API timeout and a 60 s client timeout; HTML→PDF 1–3 s

**Constraints**: no change to `lib/submitters/*`, `lib/submissions/generate_*`, `lib/pdfium.rb`, `lib/pdf_utils.rb`; edits to upstream files limited to `lib/templates/create_attachments.rb`, `lib/docuseal.rb` (`advanced_formats?`), `app/controllers/errors_controller.rb` (drop the 8 paths), `config/routes.rb` (8 routes), `spec/requests/openapi_contract_spec.rb` (empty pending list); every response documented as 422 for client-caused failure

**Scale/Scope**: single-tenant instance, tens of templates, documents ≤ 15 pages typical; 8 endpoints, ~1 200 lines of new Ruby including specs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check |
|-----------|-------|
| I. Signed documents first | No signing/result/audit file is modified. Signer-controlled input here is only the documents and parameters of authenticated API calls; every failure mode listed in FR-015 maps to a 422 in the controllers' rescue table. Redaction reuses `Page#redact` unchanged. **PASS** |
| II. Upstream is the contract | Request/response shapes taken from `docs/openapi.json`; contract spec extended to all 22 operations; CLI 1.0.4 used as the live client in the gate. **PASS** |
| III. Rebase-cheap | New files under `lib/ccn/`, `lib/templates/find_text_tag_fields.rb`, `app/controllers/api/ccn/*` (namespaced controllers mounted on the documented paths), specs under `spec/requests/ccn_*`, `spec/lib/ccn/*`. Upstream edits: 5 files, each ≤ 15 lines, listed in `CCN-CHANGES.md`. No new gems. **PASS** |
| IV. Verified independently | Request spec per endpoint + lib specs for detector/pre-processor/client; CI; diff-only review per merged slice; S2 gate scripts on staging (`staging-s2-check.sh`). **PASS** |
| V. Licence/attribution | Untouched by this feature. **PASS** |

Post-design re-check (Phase 1): unchanged, PASS.

## Project Structure

### Documentation (this feature)

```text
specs/001-documents-by-any-route/
├── plan.md              # This file
├── research.md          # Phase 0: decisions with alternatives
├── data-model.md        # Phase 1: entities and their shapes
├── quickstart.md        # Phase 1: how to exercise the feature (CLI / curl) on staging
├── contracts/README.md  # Phase 1: the 8 operations, error contract, pointer to docs/openapi.json
└── tasks.md             # Phase 2: ordered task list (speckit-tasks)
```

### Source Code (repository root)

```text
lib/
├── ccn.rb                          # Ccn namespace + configuration constants (moved from the initializer; reloadable)
├── ccn/
│   ├── gotenberg.rb                 # client: docx_to_pdf(io, filename), html_to_pdf(html, header:, footer:, size:) → PDF bytes; typed errors
│   ├── office_document.rb           # office? / convert(file) → PDF UploadedFile / error_message(e)
│   ├── text_tags.rb                 # orchestration in CreateAttachments: acro fields → tags → redact → save; store_fields
│   ├── assign_roles.rb              # transient 'role' → template.submitters (created in first-appearance order)
│   ├── html_field_tags.rb           # <x-field …> → hidden {{…;width;height}} markers (Nokogiri)
│   ├── document_params.rb           # documents[] (base64 | https URL) → UploadedFile list; explicit fields normaliser
│   ├── create_template_from_documents.rb  # name/folder/external_id upsert + CreateAttachments + schema + fields + roles
│   ├── merge_templates.rb           # clone documents of N templates, concat schema/fields, remap roles
│   ├── update_template_documents.rb # add / replace / remove / merge
│   ├── create_submission_from_documents.rb # transient template → upstream create → detach snapshot (template_id nil)
│   └── formula_bounds.rb, bounded_exponentiation.rb, bounded_shift.rb, formula_*.rb  # Stage 1 (moved here)
├── templates/
│   ├── find_text_tag_fields.rb      # detector: page.text_nodes → tags → fields + redaction rects
│   ├── create_attachments.rb        # EDIT: office → convert; PDF → Ccn::TextTags before create_document; uuid:
│   ├── process_document.rb          # EDIT (1 line): submitter_uuid ||= (tag roles survive normalisation)
│   └── replace_attachments.rb       # EDIT (1 line): same
app/controllers/application_controller.rb # EDIT: rescue_from Ccn::Gotenberg::Error → 422 / redirect with message
app/controllers/template_documents_controller.rb, templates_uploads_controller.rb # EDIT: roles added by tags persisted / conversion error reaches rescue_from
app/javascript/template_builder/builder.vue # EDIT (1 line): a field keeps the submitter its tag role assigned
app/controllers/api/
├── ccn_templates_documents_controller.rb   # POST /api/templates/{pdf,docx,html}, POST /api/templates/merge, PUT /api/templates/:id/documents
└── ccn_submissions_documents_controller.rb # (< Api::SubmissionsController) POST /api/submissions/{pdf,docx,html}
app/controllers/errors_controller.rb    # EDIT: ENTERPRISE_PATHS 404 list removed (the paths are routed now)
config/routes.rb                        # EDIT: 8 routes inside the existing :api namespace
config/locales/ccn/ccn.yml              # fork strings (en, fr)
spec/                                   # lib/ccn/*_spec, lib/templates/find_text_tag_fields_spec, requests/ccn_*_spec, requests/openapi_contract_spec (pending → [])
```

**Structure Decision**: Rails monolith; new code is flat under `lib/ccn/*.rb` (no `Ccn::Templates` sub-namespace, which would shadow `::Templates` inside the fork's own code), one detector next to its AcroForm sibling in `lib/templates`, controllers as `Api::CcnTemplatesDocumentsController` / `Api::CcnSubmissionsDocumentsController` in `app/controllers/api/` (an `Api::Ccn` namespace would make every `Ccn::X` inside them resolve to `Api::Ccn::X`), mounted on the documented paths via `config/routes.rb`. Upstream files edited: `create_attachments.rb`, `process_document.rb`, `replace_attachments.rb`, `docuseal.rb`, `application_controller.rb`, `templates_uploads_controller.rb`, `template_documents_controller.rb`, `builder.vue`, `errors_controller.rb`, `routes.rb`, the contract spec — all listed in `CCN-CHANGES.md`.

## Design decisions (summary; rationale in research.md)

1. **Detector position**: inside `CreateAttachments#handle_pdf_or_image`, after decryption and before `create_document`, because the blob must be created *after* redaction. AcroForm detection runs first (redaction flattens widgets), the detector returns `[fields, rects]`; `Page#redact(rects)` then `Document#save` produce the stored bytes. `ProcessDocument.call` is invoked with `extract_fields: false` for tagged documents and `metadata['pdf']['fields']` is set to `acro_fields + tag_fields`; untagged documents follow the upstream path unchanged. The document uuid is generated up front so both detectors can stamp `attachment_uuid`.
2. **Roles**: `find_text_tag_fields` returns fields with `role` names; `Ccn::Templates::CreateFromDocuments` (and the builder path via `ProcessDocument.normalize_attachment_fields`'s caller) maps role → `submitter_uuid`, creating `template.submitters` in first-appearance order. For the builder path (`templates_uploads_controller`, untouched) fields carry `submitter_uuid` of the first submitter as today; extra roles are added to the template by a small hook in `CreateAttachments` (`template.submitters` update) so the UI shows them.
3. **Conversion**: `Ccn::Gotenberg` uses Faraday multipart to `/forms/libreoffice/convert` and `/forms/chromium/convert/html` with `open_timeout 5 s`, `timeout 60 s`; errors → `Ccn::Gotenberg::Unavailable`, `Timeout`, `Rejected`; `CreateAttachments#handle_file_types` converts `DOCUMENT_CONTENT_TYPES`/`DOCUMENT_EXTENSIONS` to a PDF `UploadedFile` (filename `.pdf`) and recurses into `handle_pdf_or_image`. `Docuseal.advanced_formats?` → `Ccn::GOTENBERG_URL.present?` so the drop zone accepts the extensions only when conversion exists.
4. **HTML**: `Ccn::HtmlFieldTags.call(html)` rewrites each `<x-field>` into an inline-block span sized by its CSS `width/height` (px → pt × 0.75) carrying a 1-px white `{{name;type=…;role=…;width=W;height=H;…}}` marker at its top-left; Chromium renders; the detector anchors a W×H field at the marker and redacts the marker. `size` → Gotenberg `paperWidth/paperHeight` (inches table for Letter/Legal/Tabloid/Ledger/A0–A6). Header/footer HTML passed through.
5. **Template-less submissions**: `Ccn::Submissions::CreateFromDocuments` builds a transient `Template` (saved, `source: 'api'`, `preferences: {'ccn_transient' => true}`), runs the ingestion, calls upstream's `Api::SubmissionsController` private helpers through a subclass (`Params::SubmissionCreateValidator`, `create_submissions`, `Submissions.send_signature_requests`, completion loop), then detaches: copies `schema/fields/submitters` into `template_schema/template_fields/template_submitters` (already set by upstream when `submitters.completed`, else set here), re-points the document attachments (`ActiveStorage::Attachment.record`) to the submission, sets `template_id = nil`, saves, and destroys the transient template. Response: `Submissions::SerializeForApi.call(submission, params: {include: 'fields'})` + `schema`. Validated by a request spec that signs the submission through `/s/:slug` and checks the result PDF exists.
6. **Merge**: `Ccn::Templates::Merge` creates the template, then per source: `Templates::CloneAttachments.call(template:, original_template:, save: false)` pattern is not reusable directly (it clones *into* the target schema); instead new `documents_attachments` are built from each source's `schema_documents` (`blob_id` reuse, new uuid, preview images cloned via the same helper), schema concatenated, fields deep-copied with `attachment_uuid` remapped and `submitter_uuid` remapped by role name (or positionally to `roles`).
7. **Update documents**: add = `CreateAttachments.call` + schema append at `position`; replace = `Templates::ReplaceAttachments`-style remap for the one document at `position`; remove = schema/field drop; `merge: true` = `PdfUtils.merge` of all schema documents → one new document, fields' `attachment_uuid` and `page` offsets rewritten cumulatively.
8. **Errors**: one `rescue_from`-style table in each controller: `Ccn::Gotenberg::Error`, `Ccn::DocumentParams::Invalid`, `Templates::CreateAttachments::InvalidFileType`/`PdfEncrypted`, `DownloadUtils::UnableToDownload`, `Ccn::NotSupportedYet` → 422 `{error:}` with i18n messages; `Params::BaseValidator::InvalidParameterError` already handled by `Api::ApiBaseController`.
9. **Deferred with a documented 422**: `dynamic: true`, `variables`, `template_ids` (message key `ccn_not_supported_yet`).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Edit to `lib/templates/create_attachments.rb` (upstream file) | It is the single path every uploaded file takes (UI and API); hooking there gives text tags and DOCX to the builder for free | A wrapper module would have to be called from 4 controllers and 2 upstream services → more upstream edits, not fewer |
| Subclassing `Api::SubmissionsController` for `/submissions/{pdf,docx,html}` | Reuses ~150 lines of param normalisation, submitter creation, e-mail dispatch and completion handling | Reimplementing would duplicate signing-adjacent logic (Principle I) |
| Transient template then detach (design 5) | Upstream's creation services require a `template:`; the published response is template-less | Keeping a hidden template per submission clutters the templates list and diverges from the published shape |
