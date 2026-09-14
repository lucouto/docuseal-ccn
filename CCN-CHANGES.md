# CCN fork — change register

Fork of [docusealco/docuseal](https://github.com/docusealco/docuseal) (AGPL-3.0 + `LICENSE_ADDITIONAL_TERMS`) maintained by the Communauté du Chemin Neuf for
https://docuseal.cheminneuf.community. Plan and rationale: `FORK-PLAN.md` in the private ops folder (`~/Projets_apps_github/DocuSeal`).

Branches: `master` mirrors upstream tags untouched · `ccn` = this patch stack, rebased onto each upstream tag.
Release tags: `<upstream>-ccn.<n>` (e.g. `3.2.4-ccn.0`) → image `ghcr.io/lucouto/docuseal-ccn:<tag>`.

## Rules (see FORK-PLAN.md §6)

1. New files first; fill upstream's empty hook partials second; edit upstream files last and minimally.
2. One feature = one commit (or a short series). Every upstream file touched is listed below — this table is the rebase checklist.
3. Migrations additive only: the stock `docuseal/docuseal:<upstream>` image must still boot on our schema.
4. Never modify signing / result generation / audit-trail code.
5. Keep DocuSeal attribution in the UI (AGPL §7(b) additional term) and keep this repository public (AGPL §13).

## Rebase procedure

```
git fetch upstream --tags
git rebase --onto <new-tag> <old-tag> ccn        # resolve using the table below
# CI green → tag <new-tag>-ccn.1 → image builds → staging from prod snapshot → promote
```

## Upstream files touched on `ccn`

| Upstream file | Feature / commit | Why |
|---------------|------------------|-----|
| `Gemfile`, `Gemfile.lock` | Stage 1 — formulas | adds `dentaku` (MIT): server-side counterpart of the client calculator (a JS port of Dentaku) |
| `lib/submitters/submit_values.rb` | Stage 1 — formulas | replaces the two Pro stubs `calculate_formula_value` (returned 0) and `eval_text_formula_value` (returned '') |
| `app/views/templates/edit.html.erb` | Stage 1 — builder | `data-with-conditions`, `data-with-formula` |
| `app/javascript/template_builder/fields.vue` | Stage 1 — de-Pro | locked "phone" upsell tile (→ docuseal.com/pricing) removed |
| `app/javascript/submission_form/formula_areas.vue` | Stage 1 — formulas | referenced values coerced to numbers (`numericFormulaValue`) with the same rule as the server |
| `config/application.rb` | Stage 1 — i18n | `config.i18n.load_path += config/locales/ccn/**/*.yml` (after upstream's file, so keys can be overridden) |
| `app/views/shared/_settings_nav.html.erb` | Stage 1 — de-Pro | Plans/Console entries multitenant-only; SSO/SMS behind `Ccn::SSO_ENABLED`/`SMS_ENABLED`; version badge → fork release |
| `app/views/shared/_navbar_buttons.html.erb` | Stage 1 — de-Pro | "Upgrade" button on /settings removed |
| `app/views/shared/_navbar.html.erb` | Stage 1 — de-Pro | user-menu "Console" entry (→ console.docuseal.com) multitenant-only |
| `app/views/templates_preferences/show.html.erb`, `app/views/templates_code_modal/show.html.erb` | Stage 1 — de-Pro | `templates/embedding` snippets behind `Ccn::EMBEDDING_ENABLED` (embed script is a stub here; snippets link to the cloud console) |
| `app/views/shared/_powered_by.html.erb` | Stage 1 — AGPL §13 | adds the source-code link next to the DocuSeal attribution (attribution kept, §7(b)) |
| `app/views/users/_role_select.html.erb` | Stage 1 — de-Pro | upsell link removed (roles come with Stage 4) |
| `app/views/sso_settings/_placeholder.html.erb`, `sms_settings/_placeholder.html.erb`, `templates_code_modal/_placeholder.html.erb` | Stage 1 — de-Pro | render `shared/ccn_not_yet` |
| `app/views/submissions/_send_sms_button.html.erb`, `app/views/esign_settings/_default_signature_row.html.erb` | Stage 1 — de-Pro | emptied (SMS is P2; the AATL row is DocuSeal's own certificate) |
| hook partials `personalization_settings/_logo_form`, `notifications_settings/_reminder_banner`, `submissions/_list_form` | Stage 1 — de-Pro | render `shared/ccn_not_yet` until Stage 2/4 fill them |
| `lib/templates/create_attachments.rb` | Stage 2 — ingestion | `handle_file_types`: office documents → `Ccn::OfficeDocument.convert` (Gotenberg) → PDF path; `handle_pdf_or_image`: link annotations collected first, then `Ccn::TextTags.call` before the blob is created (tags → fields, erased unless `remove_tags=false`; erased pages are stored flattened), document uuid pre-generated, `ProcessDocument.call(extract_fields: false)` for tagged documents; `create_document(…, uuid:)` |
| `lib/templates/process_document.rb`, `lib/templates/replace_attachments.rb` | Stage 2 — ingestion | one line each: `f['submitter_uuid'] ||= …` so a submitter assigned from a tag role survives `normalize_attachment_fields` |
| `app/controllers/application_controller.rb` | Stage 2 — ingestion | `rescue_from Ccn::Gotenberg::Error` → JSON 422 / redirect with the translated message |
| `app/controllers/templates_uploads_controller.rb` | Stage 2 — ingestion | conversion errors skip the generic rescue (template just created is destroyed → no partial template; the translated alert is shown) |
| `app/controllers/template_documents_controller.rb` | Stage 2 — ingestion | submitters added by tag roles are saved and returned (`submitters:`) so the builder shows them |
| `app/javascript/template_builder/builder.vue` | Stage 2 — ingestion | one line: a detected field keeps the `submitter_uuid` its tag role assigned (was overwritten with the selected submitter) |
| `lib/docuseal.rb` | Stage 2 — ingestion | `advanced_formats?` → also true when `GOTENBERG_URL` is set (drop zone / upload button accept DOCX etc.) |
| `config/routes.rb` | Stage 2 — API | inside `namespace :api`: `POST templates/{pdf,docx,doc,html,merge}`, `PUT templates/:id/documents` → `Api::CcnTemplatesDocumentsController`; Phase 5 adds `POST submissions/{pdf,docx,html}` |
| `app/controllers/errors_controller.rb` | Stage 2 — API | `ENTERPRISE_PATHS` / `ENTERPRISE_FEATURE_MESSAGE` (Pro-only 404 for those paths) removed |
| `spec/requests/openapi_contract_spec.rb` | Stage 2 — API | the 5 template operations leave the pending list and get conforming-response examples |

## New files owned by the fork

| File | Purpose |
|------|---------|
| `.github/workflows/ccn-image.yml` | GHCR image build on `*-ccn.*` tags (linux/amd64) |
| `CCN-CHANGES.md` | this register |
| `lib/ccn.rb` | `Ccn` namespace: `SOURCE_URL`, `SSO_ENABLED`, `SMS_ENABLED`, `EMBEDDING_ENABLED`, `GOTENBERG_URL`, `PAGE_SIZES`, `DEFAULT_PAGE_SIZE` (env `CCN_DEFAULT_PAGE_SIZE`, default Letter), `NotSupportedYet` (moved from `config/initializers/zz_ccn.rb` in Stage 2 so the constants are reloadable and never referenced at initializer load time) |
| `lib/templates/find_text_tag_fields.rb` | text-tag detector: `{{Name;attr=…}}` (no brace inside) on `Page#text_nodes` lines (pdfium's own 4 pt/width grouping) → fields (+ transient role) and erase rectangles (`color: 'white'` = glyphs removed, nothing painted). First 200 pages only |
| `lib/ccn/text_tags.rb`, `lib/ccn/office_document.rb`, `lib/ccn/gotenberg.rb`, `lib/ccn/assign_roles.rb`, `lib/ccn/document_params.rb`, `lib/ccn/html_field_tags.rb` | Stage 2 ingestion: tag orchestration (detection guarded — a detector failure falls back to the upstream path) + erase (`save(flags: FPDF_REMOVE_SECURITY)` so a decrypted upload stays open; text extracted from an erased line loses its spaces, rendering unchanged), DOCX conversion, Gotenberg client (own multipart body, typed errors), role → submitter mapping, API `documents[]`/`fields[]` normalisation, HTML field elements → hidden tags |
| `spec/fixtures/ccn/fieldtags.pdf` (+ `build_fieldtags_pdf.rb`), `fieldtags-encrypted.pdf` | two-page A4 fixture with the 8 documented tags (generated with HexaPDF); the same file AES-encrypted with user password `secret` |
| `app/controllers/api/ccn_templates_documents_controller.rb` | `Api::CcnTemplatesDocumentsController` (not `Api::Ccn::…`, which would shadow `::Ccn`): `pdf`/`docx`/`html`/`merge`/`update`, one rescue table → 422 `{error}` (FR-015), renders `Templates::SerializeForApi` |
| `lib/ccn/create_template_from_documents.rb`, `lib/ccn/html_documents.rb`, `lib/ccn/merge_templates.rb`, `lib/ccn/update_template_documents.rb` | template creation from resolved files (`external_id` upsert via `Templates::ReplaceAttachments`, explicit fields win on name clash, `flatten` → AcroForm widgets detected then baked in by `Ccn::TextTags`), HTML → markers → Chromium → PDF (`size`, header/footer), merge (blobs shared, fresh uuids via `Templates::Clone`, roles positional or by name), add/replace/remove/merge of a template's documents (`PdfUtils`-style merge with page offsets; images become a page via `Templates::ModifyDocuments.open_or_build_pdf`) |
| `spec/fixtures/ccn/acroform.pdf` | AcroForm test PDF (text + signature widgets) for the `flatten` spec |
| `spec/requests/ccn_templates_documents_spec.rb` | US3: the five operations end to end (Gotenberg stubbed with the tag fixture) |
| `config/initializers/zz_ccn_dentaku.rb` | `to_prepare` block that prepends `Ccn::BoundedExponentiation` / `Ccn::BoundedShift` into dentaku 4.x `Exponentiation` / `BitwiseShiftLeft` / `BitwiseShiftRight` |
| `lib/ccn/formula_bounds.rb`, `lib/ccn/bounded_exponentiation.rb`, `lib/ccn/bounded_shift.rb`, `lib/ccn/formula_out_of_range.rb`, `lib/ccn/formula_not_a_number.rb` | operands of `^`, `<<`, `>>` bounded at evaluation time (base ≤ 100 digits, |exponent| ≤ 1000, base digits × |exponent| ≤ 40 000 or 15 000 for a negative exponent, shift ≤ 64; numeric string literals coerced first) → `Ccn::FormulaOutOfRange` / `Ccn::FormulaNotANumber`, turned into HTTP 422 by `Submitters::SubmitValues` |
| `config/locales/ccn/ccn.yml` | fork strings (en, fr) |
| `app/views/shared/_ccn_not_yet.html.erb` | neutral "not available on this instance yet" notice |
| `spec/requests/ccn_stage1_spec.rb` | Stage 1 gate: switches on, no upsell strings on reachable pages, attribution + source link, formulas/conditions on completion |
| `spec/requests/openapi_contract_spec.rb` + `spec/support/openapi_contract.rb` | contract test: every operation of `docs/openapi.json` is routable except the pinned PENDING list, and each implemented operation's real response matches its declared schema (dependency-free validator) |
