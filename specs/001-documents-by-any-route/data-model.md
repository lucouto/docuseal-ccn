# Data Model: Documents in, by any route

No database migration. All new data lives in existing JSON columns and ActiveStorage metadata.

## TextTag (transient, detector output)
| Attribute | Type | Notes |
|-----------|------|-------|
| name | String | first `;`-segment or `name=` attribute, squished |
| role | String, nil | `role=`; nil → first submitter |
| type | String | `type=`, default `text`; inferred `signature|initials|date` from an exact name match |
| options | [String] | `options=a,b,c` |
| required | Boolean | default true |
| readonly | Boolean | default false |
| default_value | String, nil | `default=` |
| format | String, nil | `format=` (date/number/signature preferences) |
| page | Integer | 0-based page index |
| box | {x,y,w,h} | normalised 0–1: union of the tag's character boxes, or `width/height` pt anchored top-left when given |
| redact_rects | [{x,y,w,h}] | normalised character-box union to erase (always the tag text, even when width/height override the field box) |

## Detected field (stored in `attachment.metadata['pdf']['fields']`, then `template.fields`)
Same shape as `Templates::FindPdfiumAcroFields#build_field`:
`{ uuid, name, type, required, readonly, default_value, options: [{uuid, value}], preferences: {}, areas: [{page, x, y, w, h, attachment_uuid, option_uuid?}], submitter_uuid }`
plus a transient `role` (String) consumed when roles are mapped to `template.submitters` (`[{name, uuid}]`, first-appearance order, first entry kept as default).

## Template (existing) — fields used here
`name`, `folder`, `external_id` (upsert key per account), `shared_link`, `schema: [{attachment_uuid, name}]`, `fields`, `submitters`, `preferences` (new key `ccn_transient: true` on the transient template of a document-based submission, destroyed after detach), `source: 'api'`.

## Submission (existing) — document snapshot
`template_id: nil`, `template_schema`, `template_fields`, `template_submitters`, `documents_attachments` (moved from the transient template; `preview_images` attached to each document attachment move with it), `source: 'api'`, `name`.

## Document attachment (ActiveStorage::Attachment, existing)
`uuid` (generated before creation so detectors can stamp it), blob = redacted/converted PDF, `metadata: { pdf: { number_of_pages, annotations, fields }, sha256, identified, analyzed }`.

## Conversion request (transient)
`{ io, filename, content_type } → PDF bytes` or `Ccn::Gotenberg::{Unavailable, Timeout, Rejected}`; HTML variant `{ html, header, footer, size } → PDF bytes`; page size table (inches): Letter 8.5×11, Legal 8.5×14, Tabloid 11×17, Ledger 17×11, A0 33.1×46.8, A1 23.4×33.1, A2 16.5×23.4, A3 11.7×16.5, A4 8.27×11.69, A5 5.83×8.27, A6 4.13×5.83.

## Explicit field parameter (API input → detected-field shape)
`{ name, type, role, required, title, description, options: [String], validation, preferences, areas: [{x, y, w, h, page (1-based), option}] }` → page − 1, role → submitter_uuid (creating the submitter if new), option → option_uuid, `default_value`/`readonly` for submission-level `submitters[].fields[]` handled by upstream's normaliser.

## State transitions
- Document upload: file → (convert to PDF)? → decrypt? → AcroForm fields → text tags → redact? → blob + attachment → preview images → `metadata.pdf.fields`.
- Document-based submission: transient template (created) → submission(s) created by upstream → snapshot copied, attachments re-pointed, `template_id` nil → transient destroyed. Failure before the snapshot copy destroys the transient and returns 422; nothing partial survives.
