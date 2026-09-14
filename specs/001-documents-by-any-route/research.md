# Research: Documents in, by any route

All findings from the fork's own source at tag `3.2.4` (paths relative to the repo) and DocuSeal's published
material (`docs/openapi.json`, the `fieldtags.pdf` syntax sheet, CLI 1.0.4 `--help`). Date: 2026-09-14.

## Decisions

### D1. Where to hook text-tag detection
- **Decision**: in `Templates::CreateAttachments#handle_pdf_or_image` between decryption and `create_document`.
- **Rationale**: the stored blob must be the redacted PDF; `create_document` uploads the bytes it is given, and `ProcessDocument.call` (preview images) runs after it. AcroForm detection (`FindPdfiumAcroFields.call(attachment, doc, data)`) must run *before* redaction because `Page#redact` flattens the page. The attachment uuid is only needed for `areas[].attachment_uuid`, so it is generated up front and passed to `template.documents.create!(blob:, uuid:)`.
- **Alternatives considered**: (a) a separate post-processing job — would leave the un-redacted blob visible for a while and complicate the API's synchronous contract; (b) hooking in `ProcessDocument.call` — runs after the blob exists, so redaction would require re-uploading the blob.

### D2. Text-node grouping
- **Decision**: rely on `Pdfium::Page#text_nodes`, which already sorts characters into lines (`endy` within 4 pt, then `x`), concatenate a line's characters and scan `/\{\{(.+?)\}\}/`; map match offsets back to character boxes for the bounding box; ignore tags broken across lines.
- **Rationale**: confirmed in `lib/pdfium.rb:1115-1172`; Word exports split a tag into several text runs but keep it on one line.

### D3. Tag grammar and defaults
- **Decision**: `{{name;attr=value;…}}`; `name` = first segment (or `name=`); attributes `role type options required default readonly width height format`; `type` default `text`, inferred as `signature|initials|date` when the name (case-insensitive) is exactly that word and no type is given; `required` default true; unknown type → text; `width/height` in PDF points converted to the page fraction, anchored at the tag's top-left.
- **Rationale**: the syntax sheet lists `{{Signature}}` under "Signature" next to `{{Sign here;type=signature}}`, so name inference is expected; everything else is documented literally.

### D4. Redaction
- **Decision**: `Page#redact(rects)` over each tag's character boxes (per tag, union of its char boxes, `color: 'white'` = erase the glyphs, paint nothing — any other value paints a black bar), then `Document#save(io, flags: FPDF_REMOVE_SECURITY)`; skipped when `remove_tags` is false.
- **Known cost** (review of `c8a7e493`): `redact` flattens the pages it touches and rebuilds a partially erased text run glyph by glyph, dropping blanks — the rendering is unchanged but text *extracted* from an erased line has no spaces (copy/paste, search). Link annotations are therefore collected before the erase. Accepted for Stage 2; a run-preserving rewrite is a later refinement.
- **Rationale**: `redact` flattens, removes the characters from the content stream and paints the rectangle (`lib/pdfium.rb:1173-1200`), so the tag cannot be recovered by copy/paste; it is the same primitive upstream uses for its own redaction feature.

### D5. DOCX conversion
- **Decision**: Gotenberg 8.37.0 (already running on staging), Faraday multipart `POST /forms/libreoffice/convert` (`files` part), response body = PDF; `open_timeout` 5 s, `timeout` 60 s; map connection errors → `Unavailable`, `Faraday::TimeoutError` → `Timeout`, 4xx/5xx → `Rejected(status)`. Converted file re-enters `handle_pdf_or_image` as `application/pdf` with the original basename + `.pdf`.
- **Alternatives**: running LibreOffice inside the DocuSeal image (+ 400 MB, slow cold start, memory spikes in the web process); a queue + 202 (spec says synchronous 200).

### D6. HTML field tags
- **Decision**: server-side pre-processing with Nokogiri: each `<x-field>` (list in FR-012) becomes `<span style="display:inline-block;position:relative;width:…;height:…;[original style]"><span style="position:absolute;left:0;top:0;font-size:1px;line-height:1px;color:#fff;white-space:nowrap">{{name;type=…;role=…;width=W;height=H;…}}</span></span>`; W/H = CSS px × 0.75 pt; then Chromium via Gotenberg `/forms/chromium/convert/html` with `index.html`, optional `header.html`/`footer.html`, `paperWidth/paperHeight` from the size table; then D1–D4 detect the marker and erase it (white on white anyway).
- **Rationale**: Gotenberg cannot report element positions; making elements self-describing needs one detector for three inputs. Verified: pdfium reports 1-px glyph boxes, so the marker's top-left is a reliable anchor; width/height override the tag box.

### D7. Template-less submissions
- **Decision**: transient saved template → upstream creation via a subclass of `Api::SubmissionsController` → detach (move attachments to the submission, copy snapshots, `template_id = nil`) → destroy transient.
- **Rationale**: `Submission#schema_documents` returns `documents_attachments` when `template_id` is nil (`app/models/submission.rb:129`); serializers, result/audit generators and the signing controller all guard `template&.`; the published POST `/submissions/pdf` response has no template key. `Submissions::CreateFromSubmitters.call` and `Params::SubmissionCreateValidator` need a `template:`/`template_id`, hence the transient. `maybe_require_link_2fa` (the only unguarded `template.slug`) is unreachable when the template is nil because `pass_link_2fa?` returns true first.
- **Risk & test**: a request spec creates from PDF, opens `/s/:slug`, completes with `sidekiq: :inline`, and asserts the submitter's `documents` and the audit log exist and the transient template is gone.

### D8. Page numbers and options in explicit fields
- **Decision**: `areas[].page` is 1-based on input (spec: "Starts from 1") and stored 0-based; `areas[].option` string → `option_uuid` of the field's option with that value (create the option if absent).

### D9. `external_id` upsert
- **Decision**: `Template.where(account:, external_id:).active.first` → if found, replace documents (`Templates::ReplaceAttachments`-style: new documents, fields remapped by position) and update `name`/`folder`; else create. Matches the CLI help text ("Existing template with specified external_id will be updated with a new PDF").

### D10. Default page size
- **Decision**: API default `Letter` (published spec), instance override `CCN_DEFAULT_PAGE_SIZE` (staging: `A4`) applied when `size` is absent.
- **Open for Luciano**: FORK-PLAN.md §9.7 — whether production should override to A4.

### D11. Deferred features
- `dynamic: true`, `variables`, `template_ids` → 422 `ccn_not_supported_yet` (Stage 5). The contract counts a documented 422 as implemented (FORK-PLAN.md §10 S2).

## Facts verified

- `Templates::CreateAttachments::DOCUMENT_CONTENT_TYPES` / `DOCUMENT_EXTENSIONS` exist; `handle_file_types` raises `InvalidFileType` for them today.
- `Docuseal.advanced_formats?` = `multitenant?`; used only in the two upload inputs' `accept` lists.
- `Templates::CloneAttachments`, `ReplaceAttachments`, `PdfUtils.merge(io_files)`, `DownloadUtils.call(url, validate: true)` (HTTPS only, no localhost) are available and unchanged.
- `Api::SubmissionsController` private helpers: `create_submissions(template, params)`, `submissions_params`, `build_create_json`; `before_action :maybe_return_template_error` and `load_and_authorize_resource :template` must be skipped in the subclass.
- CI image has pdfium and chromium but no LibreOffice → Gotenberg stubbed with WebMock in specs; real conversion checked by the S2 gate on staging.
- `spec/fixtures/fieldtags.docx` (upstream, unused by upstream specs) contains exactly the 8 documented tags.
