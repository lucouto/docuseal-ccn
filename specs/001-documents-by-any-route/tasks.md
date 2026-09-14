---
description: "Task list for Stage 2 — documents in, by any route"
---

# Tasks: Documents in, by any route

**Input**: Design documents from `specs/001-documents-by-any-route/` (plan.md, spec.md, research.md, data-model.md, contracts/README.md)

**Tests**: request/lib specs are part of every task (constitution IV). CI must stay green after every phase; a diff-only reviewer reads each phase before the next starts.

**Organization**: phases 1–2 are shared plumbing; phases 3–7 map to user stories US1–US5; phase 8 is the gate and release.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [x] T001 Add `Ccn::GOTENBERG_URL` (env `GOTENBERG_URL`) and `Ccn::DEFAULT_PAGE_SIZE` (env `CCN_DEFAULT_PAGE_SIZE`, default `Letter`, validated against the size table) to `config/initializers/zz_ccn.rb`; `Docuseal.advanced_formats?` → `Ccn::GOTENBERG_URL.present?` in `lib/docuseal.rb`
- [x] T002 [P] Add en/fr messages to `config/locales/ccn/ccn.yml`: `ccn_conversion_unavailable`, `ccn_conversion_timeout`, `ccn_conversion_rejected`, `ccn_invalid_document`, `ccn_not_supported_yet`, `ccn_template_not_found`
- [x] T003 [P] Generate `spec/fixtures/ccn/fieldtags.pdf` with HexaPDF (one-off script under `spec/fixtures/ccn/build_fieldtags_pdf.rb`) containing the 8 documented tags on two pages (Signer2 tags on page 2) plus a second copy of `{{Text Field}}` on page 2; commit the PDF

## Phase 2: Foundational

- [x] T004 `lib/templates/find_text_tag_fields.rb` — `call(doc, attachment_uuid)` → `[fields, redact_rects_by_page]` per data-model.md (line concatenation over `page.text_nodes`, grammar D3, name-type inference, width/height override, grouping by name+role, option uuids) + `spec/lib/templates/find_text_tag_fields_spec.rb` (8 fields from the fixture, repeated tag → 2 areas, unknown type → text, broken tag ignored, width/height box)
- [x] T005 `lib/ccn/gotenberg.rb` — Faraday multipart client: `docx_to_pdf(io, filename)`, `html_to_pdf(html, header: nil, footer: nil, size:)`, `PAGE_SIZES` table, errors `Unavailable`/`Timeout`/`Rejected` (< `Ccn::Gotenberg::Error`), timeouts 5 s / 60 s + `spec/lib/ccn/gotenberg_spec.rb` with WebMock (success, connection refused, timeout, 500)
- [x] T006 Edit `lib/templates/create_attachments.rb` (≤ 15 lines): `handle_file_types` converts `DOCUMENT_CONTENT_TYPES`/`DOCUMENT_EXTENSIONS` through `Ccn::Gotenberg.docx_to_pdf` into a PDF `UploadedFile` (basename + `.pdf`) and recurses; `handle_pdf_or_image` runs AcroForm detection, then `FindTextTagFields`, redacts unless `params[:remove_tags]` is `false`/`'false'`, saves the redacted bytes, creates the document with a pre-generated uuid, calls `ProcessDocument.call(extract_fields: false)` for tagged documents and stores `acro + tag` fields; untouched path when no tags. Register in `CCN-CHANGES.md`
- [x] T007 Role hook for the builder path (done as `Ccn::AssignRoles.call(template, fields)` called from `Ccn::TextTags.store_fields`, plus a one-line `||=` in `ProcessDocument.normalize_attachment_fields` and `ReplaceAttachments` so the assigned submitter survives) — original wording: implement `Ccn::Templates::AssignRoles.call(template, fields)` (role → existing/new `template.submitters` entry, first-appearance order, strips transient `role`) and call it from `CreateAttachments` when tag fields carry roles, so `templates_uploads_controller` and `template_documents_controller` stay untouched + spec `spec/requests/ccn_tag_upload_spec.rb` (builder upload of `fieldtags.pdf` → 8 fields, roles First Party + Signer2, preview text has no `{{`)
- [x] T008 [P] `lib/ccn/document_params.rb` — `files_from(documents, allow_html: false)` (base64 → Tempfile with Marcel type, https URL via `DownloadUtils.call(url, validate: true)`, html → placeholder handled by the HTML step), `normalize_explicit_fields(fields, template)` (1-based page → 0-based, role → submitter_uuid, option → option_uuid, types allow-list), errors `Invalid` + `spec/lib/ccn/document_params_spec.rb`
- [x] T009 [P] `lib/ccn/html_field_tags.rb` — Nokogiri rewrite of the 13 field elements to hidden `{{…;width;height}}` markers (px × 0.75), attribute carry-over (`name role required readonly default options format`), returns HTML + `spec/lib/ccn/html_field_tags_spec.rb`
- [ ] T010 [P] Routes: add inside the existing `namespace :api` in `config/routes.rb` — `scope module: :ccn do post 'templates/pdf' … end` for the 8 paths (templates/pdf|docx|html|merge, templates/:id/documents (put), submissions/pdf|docx|html); remove the 8 paths (and `/templates/doc`) from `ErrorsController::ENTERPRISE_PATHS`; register both edits in `CCN-CHANGES.md`

**Checkpoint**: CI green; reviewer pass on phases 1–2.

## Phase 3: US1 + US2 — tags and Word documents through the builder (P1)

- [x] T011 [US2] `spec/requests/ccn_docx_upload_spec.rb`: POST `/templates/:id/documents` (builder JSON endpoint) and `/templates_uploads` with `fieldtags.docx`, Gotenberg stubbed to return `spec/fixtures/ccn/fieldtags.pdf` → template with 8 fields; sidecar refused → 422 with `ccn_conversion_unavailable`; `Docuseal.advanced_formats?` true in the drop zone `accept` list when `GOTENBERG_URL` is set
- [x] T012 [US1] `remove_tags` false keeps tag text (lib spec on the saved bytes: `Pdfium::Document.open_bytes(saved).get_page(0).text_nodes` still contains `{{`)

**Checkpoint**: US1/US2 gate examples pass (SC-001 in specs).

## Phase 4: US3 — templates by API (P1)

- [ ] T013 [US3] `lib/ccn/templates/create_from_documents.rb` — `call(user:, params:, format:)`: external_id upsert (D9), folder, name (param → first document basename), `shared_link`, `CreateAttachments.call(template, {files:}, extract_fields: true)` with `remove_tags`/`flatten` (flatten → `Pdfium` flatten via existing `params[:flatten]` handling if present, else documented no-op), schema, detected ∪ explicit fields (`Ccn::DocumentParams.normalize_explicit_fields`), `AssignRoles`, `dynamic: true` → `Ccn::NotSupportedYet`, webhooks `template.created`/`template.updated`, search reindex
- [ ] T014 [US3] `app/controllers/api/ccn/templates_documents_controller.rb` — `pdf`, `docx`, `html` actions → `CreateFromDocuments` (html: `Ccn::HtmlFieldTags` + `Ccn::Gotenberg.html_to_pdf` per document, `size` default `Ccn::DEFAULT_PAGE_SIZE`), `merge` → `Ccn::Templates::Merge`, `documents` (PUT) → `Ccn::Templates::UpdateDocuments`; `authorize!(:create/:update, Template)`; rescue table → 422 (plan design 8); render `Templates::SerializeForApi.call(template)`
- [ ] T015 [US3] `lib/ccn/templates/merge.rb` (plan design 6) + `lib/ccn/templates/update_documents.rb` (design 7: add/replace/remove/merge via `PdfUtils.merge`, field `attachment_uuid` + page offsets rewritten)
- [ ] T016 [US3] `spec/requests/ccn_templates_documents_spec.rb`: pdf (base64 + URL via WebMock, explicit fields 1-based page, external_id upsert, remove_tags false, bad base64 → 422, http URL → 422, encrypted → 422), docx (stubbed Gotenberg, dynamic → 422), html (Gotenberg stub returns the tag fixture; marker rewrite asserted on the multipart body; A4 size in the request), merge (2 templates, roles remap, sources untouched, archived id → 422), documents PUT (add at position, replace keeps fields, remove drops fields, merge → 1 document)
- [ ] T017 [US3] Extend `spec/requests/openapi_contract_spec.rb`: 5 template operations get `expect_conforming_response` examples (Gotenberg stubbed); remove them from `pending_operations`

**Checkpoint**: CI green; reviewer pass on phases 3–4; tag `3.2.4-ccn.2-rc1` optional for a staging look.

## Phase 5: US4 — submissions from documents (P2)

- [ ] T018 [US4] `lib/ccn/submissions/create_from_documents.rb` — transient template (`CreateFromDocuments` with `preferences: {ccn_transient: true}`), `merge_documents` (PdfUtils.merge before ingestion), `position` ordering, detach (D7: snapshot copy, attachments re-pointed with preview images, `template_id = nil`, transient destroyed), rollback on failure; `template_ids`/`variables` → `NotSupportedYet`
- [ ] T019 [US4] `app/controllers/api/ccn/submissions_documents_controller.rb < Api::SubmissionsController` — `skip_load_and_authorize_resource :template`, `skip_before_action :maybe_return_template_error`; `pdf`/`docx`/`html` actions: build transient via T018 step 1, set `params[:template_id]`, `Params::SubmissionCreateValidator.call`, defaults, `create_submissions`, webhooks, `Submissions.send_signature_requests`, completion loop (copied from upstream `create`), detach, render `Submissions::SerializeForApi.call(submission, params: {include: 'fields'})` merged with `schema`; rescue table → 422
- [ ] T020 [US4] `spec/requests/ccn_submissions_documents_spec.rb`: pdf with role Tenant + submitter role Tenant → single submission object with `documents: []`, `schema`, `fields`, `template_id` nil, no Template left; sign through `/s/:slug` (`sidekiq: :inline`) → 200 and result documents present; `merge_documents: true` → 1 schema item; `send_email: true` → `SubmitterMailer` job enqueued (fake) but nothing else; `template_ids` → 422; docx (stub) → same; html → same; bad submitter → upstream 422 preserved
- [ ] T021 [US4] Contract spec: 3 submission operations get conforming-response examples; `pending_operations` → `[]`

**Checkpoint**: CI green; reviewer pass on phase 5.

## Phase 6: US5 — nothing 404s as Pro

- [ ] T022 [US5] Assert in the contract spec that the 8 paths never return the Pro message (`ENTERPRISE_FEATURE_MESSAGE` absent) and that `ENTERPRISE_PATHS` no longer lists them; `CCN-CHANGES.md` table updated for every touched upstream file

## Phase 7: Staging gate and release

- [ ] T023 [P] `~/Projets_apps_github/DocuSeal/staging-s2-check.sh`: CLI-driven gate against staging — create-pdf (fixture) → 8 fields + preview text check via `/api/templates/:id` document `preview_image_url` OCR-free check (download the redacted PDF via `documents[0].url`, `pdftotext` must not contain `{{`), create-docx (`fieldtags.docx`) → same 8, create-html (quickstart example, A4) → fields present, merge → 2 documents, update-documents add + merge → 1 document, submissions create-pdf `--no-send-email` → signing page 200 → completed via `PUT /s/:slug`; archive everything created; PASS/FAIL summary
- [ ] T024 Set `CCN_DEFAULT_PAGE_SIZE=A4` in `staging-compose.yml` `environment:`; tag `3.2.4-ccn.2`, GHCR build, `./staging-deploy-tag.sh 3.2.4-ccn.2`, run `staging-s1-check.sh`, `staging-s1-bounds-check.sh`, `staging-s2-check.sh`; record in `LOOP-STATE.md` (Stage 2 table + S2 gate results), update project `CLAUDE.md` cheat sheet (Pro endpoints now available on staging) and memory

## Dependencies

- Phase 2 before everything; T004 before T006/T007; T005 before T006/T011; T008/T009/T010 before T014.
- Phase 4 (T013–T015) before Phase 5 (T018 reuses `CreateFromDocuments`).
- T017/T021 last in their phases (they flip the contract).

## Parallel opportunities

- T002, T003 with T001; T008, T009, T010 with T004–T007; T015 with T014; T023 with Phase 6.
