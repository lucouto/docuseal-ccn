# Feature Specification: Documents in, by any route

**Feature Branch**: `ccn` (spec directory `001-documents-by-any-route`)

**Created**: 2026-09-14

**Status**: Draft

**Input**: User description: "Stage 2 of FORK-PLAN.md — documents in, by any route: text-tag detection in PDFs, DOCX and HTML upload through the same conversion sidecar, and the eight document-ingestion API operations that upstream reserves for Pro (create template from PDF / DOCX / HTML, merge templates, update a template's documents, create a submission from PDF / DOCX / HTML), so that Claude Code and the official CLI can drive DocuSeal end to end."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fields from text tags in a PDF (Priority: P1)

A staff member writes `{{Signature;role=Tenant;type=signature}}`-style tags into a document (Word, Google Docs, any tool), exports a PDF and uploads it in the template builder or through the API. The fields appear already positioned, typed and assigned to the right signer, and the tag text is gone from the document the signer sees.

**Why this priority**: it turns every existing document into a fillable template without clicking boxes in the editor, and it is what the DOCX and HTML routes build on.

**Independent Test**: upload DocuSeal's own `fieldtags.pdf` syntax sheet through the builder's upload button; the template opens with 8 fields of the documented names, types, roles and sizes, and the preview pages show no `{{…}}` text.

**Acceptance Scenarios**:

1. **Given** a PDF containing the 8 documented tag examples, **When** it is uploaded with field extraction on, **Then** the template has fields `Text Field` (text), `Field1` (text, role First Party), `FIeld2` (text, role Signer2), `DOB` (date), `Signature` (signature), `Sign here` (signature), `Name` (text, read-only, default "Bob"), `Test` (image, role Signer2, optional, 200 × 30 pt) and two signer roles `First Party`, `Signer2`.
2. **Given** the same PDF, **When** the template's page preview is rendered, **Then** no `{{` sequence is visible and copying the page text yields no tag text.
3. **Given** a tag repeated on two pages with the same name and role, **When** uploaded, **Then** one field exists with two areas.
4. **Given** a PDF with both AcroForm fields and text tags, **When** uploaded, **Then** both sets of fields are present.
5. **Given** the API call sets `remove_tags: false`, **When** the template is created, **Then** the tag text stays visible and the fields are still detected.

---

### User Story 2 - Word documents accepted everywhere (Priority: P1)

A staff member drops a `.docx` (or `.doc`, `.odt`, `.rtf`, `.xlsx`) on the builder, or Claude Code posts one to the API. The document is converted to PDF, previewed and treated exactly like an uploaded PDF, including text-tag detection.

**Why this priority**: CCN's documents are Word documents; converting by hand is the main friction today.

**Independent Test**: upload `fieldtags.docx` through the builder and through `docuseal templates create-docx`; both yield the same 8 fields as the PDF in Story 1.

**Acceptance Scenarios**:

1. **Given** a DOCX with the 8 tags, **When** uploaded via the builder, **Then** the template shows a PDF preview and the same 8 fields as Story 1.
2. **Given** the conversion service is unreachable, **When** a DOCX is uploaded, **Then** the user receives an explicit "document conversion unavailable" error and no half-created template.
3. **Given** a DOCX flagged `dynamic: true` (variables templating), **When** posted to the API, **Then** the response is a documented 422 explaining the option is not supported yet.

---

### User Story 3 - Templates created and reshaped by API (Priority: P1)

Claude Code (or any client using the official CLI or SDKs) creates a template from a PDF, DOCX or HTML payload, merges several templates into one, and adds, replaces or removes a template's documents, using the exact request and response shapes DocuSeal publishes.

**Why this priority**: this is the P0 goal of the fork: the API becomes complete for document ingestion and the official tooling works against this instance unchanged.

**Independent Test**: run `docuseal templates create-pdf --file x.pdf --name T`, `create-docx`, `create-html`, `merge`, `update-documents` against staging; each returns 200 with a template that opens in the editor.

**Acceptance Scenarios**:

1. **Given** a base64 PDF with tags, **When** `POST /api/templates/pdf` is called with `name` and `folder_name`, **Then** a template is created in that folder with detected fields plus any `fields` given explicitly (page numbers given 1-based, stored 0-based) and the response validates against the published template schema.
2. **Given** an `external_id` that already exists in the account, **When** `POST /api/templates/pdf` is called again, **Then** the existing template gets the new document(s) and name instead of a duplicate being created.
3. **Given** two templates with different signer roles, **When** `POST /api/templates/merge` is called with `template_ids` and `roles`, **Then** one new template holds both documents in order, all fields remapped to the given roles, and the source templates are untouched.
4. **Given** a template with two documents, **When** `PUT /api/templates/{id}/documents` adds one, replaces one at `position`, and removes one, **Then** the schema reflects the operations, fields of a replaced document move to the replacement, fields of a removed document are dropped, and `merge: true` combines all documents into a single PDF.
5. **Given** HTML with `<signature-field>` and `<text-field>` elements sized in CSS pixels, **When** `POST /api/templates/html` is called, **Then** the rendered page carries fields at the element positions with the element's size and no visible marker, and `size` (Letter, A4, …) sets the page size.
6. **Given** a document given as an HTTPS URL instead of base64, **When** any ingestion endpoint is called, **Then** the file is fetched and processed the same way; `http://`, localhost and unreachable URLs yield a 422.

---

### User Story 4 - One-shot signature requests from a document (Priority: P2)

Claude Code sends a PDF, DOCX or HTML plus the signers in a single call and gets back a submission ready to sign, without a template appearing in the templates list.

**Why this priority**: it is the most direct "send this for signature" flow for an agent; it depends on Story 3's ingestion pieces.

**Independent Test**: `docuseal submissions create-pdf --file x.pdf -d 'submitters[0][email]=…' --no-send-email` returns a submission whose signing link opens and can be completed; no new template is listed.

**Acceptance Scenarios**:

1. **Given** a PDF with tags for role "Tenant" and a submitter with `role: Tenant`, **When** `POST /api/submissions/pdf` is called with `send_email: false`, **Then** the response is a single submission object with `documents`, `schema`, `fields` and the submitter; the signing page loads the document and completion produces a signed PDF and audit trail.
2. **Given** several documents with `position`, **When** created with `merge_documents: true`, **Then** the signer sees one combined document.
3. **Given** `template_ids` mixing existing templates with new documents, or DOCX `variables`, **When** called, **Then** the response is a documented 422 (deferred features).
4. **Given** `send_email: true` on staging, **When** called, **Then** nothing is e-mailed (no SMTP configured) and the API still returns 200.

---

### User Story 5 - Nothing 404s as "Pro" any more (Priority: P3)

The eight operations no longer answer "This feature is available in Pro Edition"; the contract test covers all 22 documented operations.

**Independent Test**: `spec/requests/openapi_contract_spec.rb` has an empty pending list and passes.

**Acceptance Scenarios**:

1. **Given** the fork build, **When** any of the 8 paths is called with valid parameters, **Then** it is served (200 or a documented 422), never the Pro 404.

---

### Edge Cases

- Tag split across text runs or lines by the PDF producer (Word often splits `{{Name;type=…}}` into several runs): the detector works on the concatenated characters of a line, so runs do not matter; a tag broken across two lines is not detected and is left in place.
- Tag with unknown `type` → text; unknown attribute → ignored; malformed tag (no closing `}}`) → left as text.
- Two tags with the same name but different roles → two fields.
- Tag without role in a document whose other tags name roles → first role ("First Party").
- White (invisible) tag text: detected the same way, redaction paints white over white.
- Encrypted PDF → existing "PDF encrypted" 422; zip uploads → each entry processed as today.
- Documents over the existing size limits keep upstream's behaviour (no preview beyond the limit, no field extraction above 20 MB).
- Conversion time-out (large DOCX): a 422 "conversion timed out", nothing created.
- `merge` with a document that is an image, not a PDF: images are rasterised into PDF pages before merging.
- Merged templates with duplicate field names across sources keep both fields (uuids differ); roles are matched by name, positionally when `roles` is given.
- `PUT documents` with `position` beyond the end appends; `replace` with no existing document at that position adds.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST detect `{{name;attr=value;…}}` tags in every uploaded or API-provided PDF page and create one field per unique (name, role) with one area per occurrence, supporting `role`, `type` (text, signature, initials, date, image, file, select, checkbox, radio, number, cells, stamp, phone, multiple), `options`, `required` (default true), `default`, `readonly` (default false), `width` and `height` in points (default: the tag's own box).
- **FR-002**: The system MUST infer type `signature`, `initials` or `date` from a tag whose name is exactly that word when no `type` is given, and default to `text` otherwise.
- **FR-003**: The system MUST remove tag text from the stored document by default and keep it when `remove_tags: false` is given; the stored document is what signers and result PDFs use.
- **FR-004**: The system MUST create signer roles from tag roles in order of first appearance, keeping the first role as the default for untagged fields.
- **FR-005**: The system MUST accept Word/OpenDocument/RTF/Excel documents (`.docx .doc .odt .rtf .xlsx .xls`) wherever a PDF is accepted (builder upload, drop zone, API), convert them to PDF through the configured conversion service and then process them as PDFs; the original filename is kept with a `.pdf` extension.
- **FR-006**: The system MUST answer conversion-service failures with HTTP 422 and a message naming the cause (unavailable, timed out, rejected file), leaving no partial template.
- **FR-007**: The system MUST implement `POST /api/templates/pdf`, `POST /api/templates/docx`, `POST /api/templates/html`, `POST /api/templates/merge`, `PUT /api/templates/{id}/documents`, `POST /api/submissions/pdf`, `POST /api/submissions/docx`, `POST /api/submissions/html` with the request and response schemas of `docs/openapi.json`, accepting documents as base64 or HTTPS URL, and remove them from the Pro 404 list.
- **FR-008**: Explicit `fields` in ingestion requests MUST be honoured with 1-based `page` converted to the stored 0-based index, `role` resolved to a signer, `option` resolved to the option uuid for radio/multiple areas, and merged with detected fields (explicit wins on name clash).
- **FR-009**: `external_id` on template creation MUST upsert: an existing active template with that id in the account receives the new documents and name; otherwise a template is created.
- **FR-010**: `POST /api/templates/merge` MUST clone the documents of the given templates in order, concatenate schema and fields, map each source template's roles onto `roles` when given (positionally) or keep source roles by name otherwise, and leave the sources unchanged.
- **FR-011**: `PUT /api/templates/{id}/documents` MUST support add (default), `replace` at `position`, `remove`, documents given as `file` (PDF/DOCX/image, base64 or URL) or `html`, and `merge: true` producing one combined PDF document; fields keep their positions on replacement.
- **FR-012**: HTML ingestion MUST support the field elements `text-field, signature-field, initials-field, date-field, image-field, file-field, select-field, checkbox-field, radio-field, number-field, phone-field, stamp-field, cells-field` with attributes `name role required readonly default options format` and CSS `width/height`, render with the requested page `size` (Letter default per the published spec; the instance default is configurable), and produce fields at the rendered element positions with no visible marker.
- **FR-013**: Submissions created from documents MUST carry their own document snapshot (documents, schema, fields, signer roles) and no template row, honour `submitters[]` with roles, values, `send_email`, `order`, `message`, `expire_at`, `completed_redirect_url`, `bcc_completed`, `reply_to`, and `merge_documents`, and return the single-submission response of the spec.
- **FR-014**: `dynamic: true`, `variables`, and `template_ids` MUST answer HTTP 422 with an explicit "not supported yet" message (deferred to a later stage).
- **FR-015**: Every failure a client can cause (bad base64, wrong content type, missing required parameter, unreachable URL, sidecar down) MUST be a 422 with a plain-language `error`; nothing signer- or client-controlled may produce a 500.
- **FR-016**: The contract test MUST exercise all 22 documented operations and its pending list MUST be empty.

### Key Entities *(include if feature involves data)*

- **Text tag**: a `{{…}}` occurrence on a page: name, attributes, page index, bounding box (normalised 0–1), and the characters to erase.
- **Detected field**: same shape as an AcroForm-detected field (uuid, name, type, required, readonly, default_value, options, preferences, areas[page, x, y, w, h, attachment_uuid, option_uuid]) plus the signer role name it belongs to.
- **Document snapshot** (submission from documents): documents attached to the submission, `template_schema`, `template_fields`, `template_submitters` stored on the submission; `template_id` empty.
- **Conversion request**: source file + filename → PDF bytes, or a typed failure (unavailable, timeout, rejected).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `fieldtags.pdf` and `fieldtags.docx` uploaded through the builder and through the API each yield exactly the 8 documented fields with the documented types, roles and read-only/default/size attributes, and the page preview contains no tag text.
- **SC-002**: All five Pro template commands and `submissions create-pdf` of the official CLI 1.0.4 succeed against staging with a 200 and the created objects open in the editor / signing page.
- **SC-003**: The contract test passes for 22 of 22 documented operations.
- **SC-004**: Converting a 10-page Word document and creating its template completes within the API client's 60 s timeout on staging; a typical 1–3 page DOCX completes in under 10 s.
- **SC-005**: A submission created from a PDF by API can be completed on its signing page and produces a signed PDF and audit trail, with no template visible in the templates list.
- **SC-006**: No request in the new endpoints' specs or on staging returns HTTP 500 for malformed input (bad base64, unsupported type, bad URL, sidecar stopped).

## Assumptions

- Page size default follows the published spec (Letter) so the CLI and SDK documentation stay accurate; the instance can override the default (staging: A4) — recorded for Luciano (FORK-PLAN.md §9.7).
- Submissions created from documents are template-less (own snapshot); this matches the published response (no template in the required keys) and the codebase's existing nil-template guards.
- The conversion sidecar (Gotenberg 8.37.0) is already deployed on staging with `GOTENBERG_URL`; production will get the same sidecar at promotion time.
- Tag detection covers the documented grammar plus the field types the HTML route needs; verification/payment/KBA field types are out of scope (Tier C in FORK-PLAN.md).
- DOCX `[[variables]]` templating, `template_ids` mixing and `variables` stay deferred to Stage 5 and answer a documented 422.
- HTML rendering uses the same sidecar (Chromium route); remote fetches from HTML are denied by the sidecar's configuration.
- Existing upstream limits (file size, pages processed, preview generation) are unchanged.
