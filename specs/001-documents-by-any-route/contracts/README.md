# Contracts: the eight ingestion operations

Source of truth: upstream `docs/openapi.json` (copy in `../../../DocuSeal/openapi-upstream-3.2.4.json` on the workstation). The contract test `spec/requests/openapi_contract_spec.rb` validates every response against the spec's declared 200 schema; after this feature its `pending_operations` list is empty.

| Operation | Request (top level; `*` required) | Response | Documented 422s (fork) |
|-----------|-----------------------------------|----------|------------------------|
| `POST /api/templates/pdf` | `documents*[]{name*, file* (base64 or https URL), fields[]}`, `name`, `folder_name`, `external_id`, `shared_link` (true), `flatten` (false), `remove_tags` (true) | Template (same as `GET /templates/{id}`) | invalid base64 / content type, encrypted PDF, URL not https / unreachable |
| `POST /api/templates/docx` | as pdf + `documents[].dynamic` (false) | Template | as pdf + conversion unavailable / timed out / rejected; `dynamic: true` → not supported yet |
| `POST /api/templates/html` | `html*`, `html_header`, `html_footer`, `size` (Letter; instance override), `name`, `folder_name`, `external_id`, `shared_link`, `documents[]{html*, name}` | Template | conversion errors; empty html |
| `POST /api/templates/merge` | `template_ids*[]`, `name`, `folder_name`, `external_id`, `shared_link`, `roles[]` | Template | unknown / inaccessible / archived template id, fewer than 1 id |
| `PUT /api/templates/{id}/documents` | `documents[]{name, file, html, position, replace (false), remove (false)}`, `merge` (false) | Template | as pdf/html; position without document to replace/remove |
| `POST /api/submissions/pdf` | `documents*[]{name*, file*, fields[], position}`, `submitters*[]`, `name`, `send_email` (true), `send_sms`, `order`, `completed_redirect_url`, `bcc_completed`, `reply_to`, `expire_at`, `message{}`, `flatten`, `merge_documents`, `remove_tags`, `template_ids[]` | one Submission object (`id, submitters, source, submitters_order, status, documents, expire_at, created_at` required; plus `schema`, `fields`) | ingestion errors; upstream's submitter validation errors; `template_ids` → not supported yet |
| `POST /api/submissions/docx` | as pdf (documents are DOCX) + `variables{}` | Submission | + conversion errors; `variables` → not supported yet |
| `POST /api/submissions/html` | `documents*[]{name, html*, html_header, html_footer, size, position}`, submitters etc. | Submission | conversion errors |

## Error contract
Every client-caused failure: HTTP 422, body `{"error": "<plain-language message>"}` (translated: `ccn_conversion_unavailable`, `ccn_conversion_timeout`, `ccn_conversion_rejected`, `ccn_invalid_document`, `ccn_not_supported_yet`, plus upstream's existing messages). Authentication and authorisation errors keep upstream's 401/403. No client input may yield a 500.

## Client compatibility
Official CLI 1.0.4 sends `--file` as base64 in `documents[0][file]`, `areas[].page` 1-based, and expects the response shapes above. SDKs follow the same spec.
