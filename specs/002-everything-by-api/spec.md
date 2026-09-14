# Feature Specification: Everything else by API

**Feature Branch**: `ccn` (spec directory `002-everything-by-api`)

**Created**: 2026-09-14

**Status**: Draft

**Input**: User description: "Stage 3 of FORK-PLAN.md — everything else by API (rest of P0-A): the functions that are UI-only even in DocuSeal Pro become API operations under `/api/ccn/...` (users, webhooks, account settings, template folders, template versions, field detection), template preferences become writable through `PUT /api/templates/{id}`, matching MCP tools let Claude Code drive the same functions natively, and the fork publishes its own OpenAPI reference so that Claude Code (and any client) can administer the instance end to end without a browser."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Users administered by API (Priority: P1)

An administrator (or Claude Code acting for one) lists the account's users, invites a colleague, corrects a name, archives a user who left, and triggers a password reset, all through the REST API with the account's API token.

**Why this priority**: onboarding and offboarding staff is the most frequent administrative task and the one Claude Code cannot do today without a browser session.

**Independent Test**: from this Mac, `POST /api/ccn/users` with a new e-mail creates an active user visible in Settings → Users; `DELETE /api/ccn/users/{id}` archives it; both appear in the list filters.

**Acceptance Scenarios**:

1. **Given** an account with three users, **When** `GET /api/ccn/users` is called, **Then** the active users are returned with `id`, `email`, `first_name`, `last_name`, `role`, `archived_at`, sign-in timestamps, and never a token, password or internal uuid; `?status=archived` returns the archived ones and `?status=integration` the integration users.
2. **Given** a new e-mail address, **When** `POST /api/ccn/users` is called with `email`, `first_name`, `last_name`, **Then** an active user is created with the default role, an invitation e-mail is queued unless `send_email: false`, and the response is the created user.
3. **Given** the e-mail of an archived user, **When** `POST /api/ccn/users` is called with it, **Then** that user is reactivated (as the UI does) instead of a duplicate being created; **Given** the e-mail of an active user, **Then** the response is a documented 422 "already exists".
4. **Given** a user, **When** `PUT /api/ccn/users/{id}` changes `first_name`, `last_name`, `email`, `otp_required_for_login` or `archived_at`, **Then** the changes are saved and returned; `password` is refused (422) — as in the UI it is set at invitation only and reset by e-mail afterwards; a changed e-mail takes effect immediately (Devise confirmable is not enabled in this edition, so the UI's reconfirmation branch never runs).
5. **Given** the caller's own user, **When** it tries to archive itself or to change its own role or 2FA requirement, **Then** the request is refused with a documented 422 (the UI's own guard).
6. **Given** a user who has not received a reset e-mail in the last 10 minutes, **When** `POST /api/ccn/users/{id}/reset_password` is called, **Then** the reset e-mail is sent and the response is 200; a second call within 10 minutes is a documented 422 "already sent".

---

### User Story 2 - Webhooks administered by API (Priority: P1)

Claude Code connects DocuSeal to n8n: it registers a webhook URL with the events it needs, sets the shared secret header, reads the delivery log when something looks wrong, resends a failed event, fires a test event, and removes the webhook when the integration is retired.

**Why this priority**: webhooks are how DocuSeal reaches the rest of CCN's stack (n8n, CRM); today each change needs Settings → Webhooks.

**Independent Test**: `POST /api/ccn/webhooks` with an n8n test URL, `PUT` its events and secret, `POST …/test`, `GET …/events` shows the test delivery, `DELETE` removes it.

**Acceptance Scenarios**:

1. **Given** a valid https URL and a list of event names, **When** `POST /api/ccn/webhooks` is called, **Then** the webhook is created with exactly those events (default: the four `form.*` events when omitted) and the response carries `id`, `url`, `events`, `secret_key`, timestamps; secret values are not in the response.
2. **Given** an unknown event name or a URL that is not http(s), **When** the webhook is created or updated, **Then** the response is a documented 422 naming the offending value.
3. **Given** a webhook, **When** `PUT /api/ccn/webhooks/{id}` sends `secret: { key: "X-Token", value: "…" }`, **Then** subsequent deliveries carry that header; `secret: {}` removes it; `GET /api/ccn/webhooks/{id}/secret` reveals the custom header and the HMAC signing secret to the administrator (and nothing else does).
4. **Given** a webhook with past deliveries, **When** `GET /api/ccn/webhooks/{id}/events?status=error` is called, **Then** the failed deliveries are listed newest first with `uuid`, `event_type`, `record_type`, `record_id`, `status`, attempts (status code, time), paginated like the other lists.
5. **Given** a delivery, **When** `POST /api/ccn/webhooks/{id}/events/{uuid}/resend` is called, **Then** the same event is queued again for that webhook and the response is 200.
6. **Given** at least one completed submitter in the account, **When** `POST /api/ccn/webhooks/{id}/test` is called, **Then** a test `form.completed` delivery is queued to that webhook; with no completed submitter the response is a documented 422.
7. **Given** a webhook, **When** `DELETE /api/ccn/webhooks/{id}` is called, **Then** it no longer receives events and is gone from the list.

---

### User Story 3 - Account settings by API (Priority: P1)

Claude Code reads the account's settings (signing options, e-mail templates, reminders, BCC, completion message) and changes them: for example, it sets the French invitation e-mail subject and body, enables reminders at 1 day and 3 days, and turns typed signatures off, then reverts the change.

**Why this priority**: settings drive every signature flow; being able to read and set them from the API is what makes the instance fully manageable, and it is the foundation for the Stage 4 features (reminders, logo).

**Independent Test**: `GET /api/ccn/account_configs` lists every allowed key with its value or default; `PUT /api/ccn/account_configs/allow_typed_signature` with `{ "value": false }` changes the signing form; `DELETE` restores the default.

**Acceptance Scenarios**:

1. **Given** the account, **When** `GET /api/ccn/account_configs` is called, **Then** every key of the allow-list is returned with `key`, `value` (null when unset), `default` (for the keys that have one) and `type` (`boolean`, `string`, `object`); `GET /api/ccn/account_configs/{key}` returns one.
2. **Given** an allowed key, **When** `PUT /api/ccn/account_configs/{key}` is called with a `value` of the right type, **Then** it is stored and takes effect immediately (the signing form, the e-mails, the reminders read it); a value of the wrong type is a documented 422.
3. **Given** a key that is not in the allow-list, including every encrypted configuration (SMTP, storage, e-signature certificates, application URL, timestamp server), **When** it is read or written, **Then** the response is a documented 422 "unknown setting" and nothing is stored or revealed.
4. **Given** a key with a stored value, **When** `DELETE /api/ccn/account_configs/{key}` is called, **Then** the stored value is removed and the instance falls back to the default.
5. **Given** the reminders key, **When** `PUT` sends `{ "value": { "first_duration": "twenty_four_hours", "second_duration": "three_days" } }`, **Then** the durations are validated against the instance's duration table and stored in the shape the UI writes.

---

### User Story 4 - Templates fully configurable by API (Priority: P1)

Claude Code finishes a template it created from a document: it sets the per-template e-mail subject and body, the completion redirect URL, the expiry, and moves it into a folder it created; later it lists the template's versions, snapshots the current state and restores a previous one; on an uploaded scan it asks the ML field detector for candidate fields.

**Why this priority**: Stage 2 made templates *creatable* by API; this closes the remaining UI-only steps between "created" and "ready to send".

**Independent Test**: `PUT /api/templates/{id}` with `preferences: { request_email_subject: "…" }` shows the subject in the template's preferences drawer; `POST /api/ccn/template_folders` then `PUT /api/templates/{id}` with `folder_name` moves it; `POST /api/ccn/templates/{id}/versions` then `…/restore` round-trips the fields.

**Acceptance Scenarios**:

1. **Given** a template, **When** `PUT /api/templates/{id}` is called with `preferences` holding any of the UI's per-template preference keys (request/invitation/reminder/documents-copy/completion e-mails, redirect URL, default expiry, 2FA requirements, submitters order, BCC, completed message, link form fields), **Then** they are stored with the UI's coercions (booleans, expiry in the account's timezone) and returned by `GET /api/templates/{id}`; a `null` value removes the key; an unknown key is a documented 422.
2. **Given** the account, **When** `GET /api/ccn/template_folders` is called, **Then** active folders are listed with `id`, `name`, `full_name`, `parent_folder_id`, `templates_count`; `POST` with `name` (or `"Parent / Child"`) creates or returns the folder; `PUT` renames it (the default folder cannot be renamed: 422); `DELETE` archives an empty folder (a folder with active templates or subfolders: 422).
3. **Given** a template with versions, **When** `GET /api/ccn/templates/{id}/versions` is called, **Then** the versions are listed newest first with author and date; `GET …/versions/{version_id}` returns the version's name, schema, submitters, fields and documents; `POST …/versions` records the current state (idempotent: an unchanged template yields the same version).
4. **Given** a version whose documents still belong to the template, **When** `POST …/versions/{version_id}/restore` is called, **Then** the current state is recorded as a version first, then the template's name, schema, submitters, variables and fields are replaced by the version's; a version referencing a document since removed is a documented 422 and nothing changes.
5. **Given** a template with documents, **When** `POST /api/ccn/templates/{id}/detect_fields` is called, **Then** the detector's candidate fields are returned per document and page (type, name, area) without changing the template; with `apply: true` they are added to the template's fields under the first signer; a template without documents is a documented 422.

---

### User Story 5 - The same functions as MCP tools (Priority: P2)

From Claude Code with the DocuSeal MCP server registered, the user says "invite alice@chemin-neuf.org", "add an n8n webhook for completed forms", "set the invitation e-mail in French", "create a template from this PDF and send it to Bob" and Claude Code does it through MCP tools, without writing curl commands.

**Why this priority**: REST is the primary surface (CLI, n8n); MCP mirrors it for conversational use. Valuable, but everything is already reachable over REST.

**Independent Test**: `tools/list` on `/mcp` lists the new tools next to upstream's five; each new tool is exercised once from Claude Code against staging.

**Acceptance Scenarios**:

1. **Given** an MCP token of an account with MCP enabled, **When** `tools/list` is called, **Then** the upstream tools and the fork tools (`create_template_from_documents`, `update_template_documents`, `merge_templates`, `create_submission_from_documents`, `manage_users`, `manage_webhooks`, `account_config`, `set_template_preferences`) are listed with JSON schemas.
2. **Given** a `tools/call` on a fork tool with valid arguments, **Then** the tool performs the same operation as the REST endpoint (same service, same validations) and returns the same data as text content; an invalid argument returns an MCP tool error carrying the same 422 message, never a protocol error.
3. **Given** a token whose account has MCP disabled or a user who cannot manage the resource, **Then** the call is refused as upstream refuses (403 / forbidden), unchanged.

---

### User Story 6 - Reference and cheat sheet for Claude Code (Priority: P2)

Claude Code (and any developer) reads one OpenAPI document describing the fork-only operations, and the project cheat sheet lists every operation the deployed instance answers.

**Why this priority**: an API nobody can discover is not "manageable by API".

**Independent Test**: `docs/openapi-ccn.json` validates as OpenAPI 3.1 and every operation in it is routable and answers with a conforming response in the contract spec; `CLAUDE.md` (project directory) lists the same operations.

**Acceptance Scenarios**:

1. **Given** `docs/openapi-ccn.json`, **When** the contract spec runs, **Then** every operation is routed by the application and every 200 response validates against its schema; the upstream contract spec keeps passing for the 22 upstream operations.
2. **Given** the `preferences` extension of `PUT /api/templates/{id}`, **Then** it is documented in the fork file as an extension of the upstream operation (the upstream file is not edited).

---

### Edge Cases

- Archiving or demoting the calling user, or changing its own 2FA requirement → 422 (the UI forbids the same).
- Inviting an e-mail that exists in another account → 422 "already exists" (never reveal which account).
- Reset password for an archived user → 422.
- Webhook URL pointing at localhost or a private address: accepted as upstream accepts it (single-tenant instance; the UI accepts any URL). Events list for a webhook of another account → 404.
- Setting `enable_mcp` to false through the API disables MCP for the account, including the caller's own MCP session; allowed, documented.
- Config values: `'true'`/`'false'`/`'1'`/`'0'` strings are coerced to booleans for boolean keys (the UI sends `'1'`/`'0'`); objects for e-mail templates are stored with blank members removed; a blank value on a key with a default removes the stored row (as the UI does).
- Template preferences: `default_expire_at` given without a timezone is interpreted in the account's timezone and stored in UTC (the UI's behaviour); `submitters` per-signer e-mails are stored as given (the UI's `request_email_per_submitter` toggle has no API meaning).
- Folder creation with `"A / B / C"` (three levels) → the UI supports two levels; `"A / B / C"` is refused with 422.
- Restore when the template has been edited concurrently: the pre-restore snapshot preserves the concurrent state; no locking.
- Field detection on a template with more than 30 pages in total → 422 (the detector runs synchronously in the request).
- MCP: a tool called with `documents[].file` as a `data:` URI or base64 works like the REST endpoint; URLs are downloaded with the same validation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST expose `/api/ccn/users` (`GET` list with `status` filter, `POST` invite), `/api/ccn/users/{id}` (`GET`, `PUT`, `DELETE` = archive) and `/api/ccn/users/{id}/reset_password` (`POST`), accepting exactly the attributes the UI permits (`email first_name last_name password archived_at otp_required_for_login role`; `password` at invitation only), with the UI's guards (self-archive/self-role/self-2FA refused, `role` accepted only from `User::ROLES`, reactivation of an archived e-mail, 10-minute reset throttle) and the UI's side effects (invitation e-mail unless `send_email: false`, Devise reset instructions).
- **FR-002**: The system MUST expose `/api/ccn/webhooks` (`GET`, `POST`), `/api/ccn/webhooks/{id}` (`GET`, `PUT`, `DELETE`), `/api/ccn/webhooks/{id}/secret` (`GET`), `/api/ccn/webhooks/{id}/events` (`GET` with `status` filter), `/api/ccn/webhooks/{id}/events/{uuid}/resend` (`POST`) and `/api/ccn/webhooks/{id}/test` (`POST`); events MUST be validated against `WebhookUrl::EVENTS`; `secret` MUST be a single `{ key, value }` header replaced whole; list and show responses MUST NOT contain secret values.
- **FR-003**: The system MUST expose `/api/ccn/account_configs` (`GET`) and `/api/ccn/account_configs/{key}` (`GET`, `PUT`, `DELETE`) for the union of the keys the three UI settings controllers allow (`AccountConfigsController::ALLOWED_KEYS`, `PersonalizationSettingsController::ALLOWED_KEYS`, `bcc_emails`, `submitter_reminders`), each with a declared type (boolean, string, object) and the UI's coercions; every other key, and every `EncryptedConfig` key, MUST be refused with 422 and never read.
- **FR-004**: `PUT /api/templates/{id}` MUST accept `preferences` (top level or under `template`) limited to the keys `TemplatesPreferencesController` permits, with its coercions (booleans, `default_expire_at` in the account timezone, blank values removed); `null` MUST remove a key; an unknown key MUST be a 422; the upstream response (`id`, `updated_at`) and side effects (`template.updated` webhook) MUST be unchanged.
- **FR-005**: The system MUST expose `/api/ccn/template_folders` (`GET`, `POST`) and `/api/ccn/template_folders/{id}` (`PUT`, `DELETE`); `POST` MUST reuse `TemplateFolders.find_or_create_by_name` semantics (two levels, `"Parent / Child"`); renaming the default folder MUST be refused; `DELETE` MUST archive only a folder without active templates or subfolders.
- **FR-006**: The system MUST expose `/api/ccn/templates/{id}/versions` (`GET`, `POST`), `/api/ccn/templates/{id}/versions/{version_id}` (`GET`) and `…/restore` (`POST`), reusing `TemplateVersions`; restore MUST snapshot the current state first and MUST refuse (422, no change) a version whose schema references a document the template no longer has.
- **FR-007**: The system MUST expose `/api/ccn/templates/{id}/detect_fields` (`POST`, optional `attachment_uuid`, `page`, `apply`) running `Templates::DetectFields` synchronously and returning the candidates grouped by document and page; `apply: true` MUST add them as fields of the first submitter without duplicating existing fields (same name, same area).
- **FR-008**: Every `/api/ccn/...` operation MUST authenticate with `X-Auth-Token` exactly like the upstream API, authorize through the account's abilities (`manage` on the resource's class, `update` on a template), paginate lists like upstream (`limit`, `after`, `before`, `{ data, pagination }`), and answer client errors as `422 { error }` (validation, unknown key, refused guard) or `404` (foreign or missing record) — never a 500 for client-controlled input.
- **FR-009**: The system MUST register MCP tools `create_template_from_documents`, `update_template_documents`, `merge_templates`, `create_submission_from_documents`, `manage_users`, `manage_webhooks`, `account_config` and `set_template_preferences`, each delegating to the same service module as its REST counterpart, with a JSON schema, and returning validation failures as MCP tool errors (`isError: true`) carrying the REST 422 message.
- **FR-010**: The fork MUST ship `docs/openapi-ccn.json` (OpenAPI 3.1, same style as upstream: `AuthToken` security scheme, inlined schemas, examples) describing every `/api/ccn/...` operation and the `preferences` extension of `PUT /templates/{id}`; a contract spec MUST assert that every documented operation is routable and that its 200 response validates against its schema; the upstream contract spec MUST keep passing.
- **FR-011**: Every touched upstream file (`config/routes.rb`, `app/controllers/api/templates_controller.rb`, `app/controllers/mcp_controller.rb`) MUST be listed in `CCN-CHANGES.md`; no upstream file is edited beyond the minimum hook (one call, a route block, a hash entry per tool); no migration; no new gem.
- **FR-012**: The project cheat sheet (`CLAUDE.md` in the operations directory) MUST list every operation the deployed staging instance answers after this stage, including the upstream ones already available for unarchiving (`PUT /api/submissions/{id}` `archived: false`, `PUT /api/templates/{id}` `archived: false`) and resending (`PUT /api/submitters/{id}` with `send_email`).
- **FR-013**: Out of scope, documented as such: submitter resubmit (a signer self-service tied to the signed-in user's e-mail), template access/sharing lists (needs the Stage 4 roles), folder deletion that moves templates, and any secret of `EncryptedConfig`, the API token or MCP tokens.

### Key Entities

- **User**: account member; `role` (`admin` today), `archived_at`, sign-in timestamps; never exposes password digest, tokens or uuid.
- **WebhookUrl**: `url`, `events[]` (from `WebhookUrl::EVENTS`), `secret` (`{header => value}`, write-only), `hmac_secret` (generated; revealed only by the secret endpoint); has many **WebhookEvent** (`uuid`, `event_type`, `record_type/record_id`, `status`) each with **WebhookAttempt** (`attempt`, `response_status_code`, `created_at`).
- **AccountConfig**: `key` (allow-listed), `value` (JSON: boolean, string or object per key), optional default from `AccountConfig::DEFAULT_VALUES`.
- **Template preferences**: the free-form `preferences` hash of a template, restricted to the UI's key list.
- **TemplateFolder**: `name`, `parent_folder_id` (two levels), `archived_at`; the account's default folder is immutable.
- **TemplateVersion**: `data` (name, schema, submitters, variables_schema, fields, dynamic documents), `sha1`, `author`.
- **Detected field candidate**: `type`, `name`, `area` (page, x, y, w, h, attachment uuid) as produced by `Templates::DetectFields`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every row of FORK-PLAN.md §3.2 that is in scope has a request spec and an entry in `docs/openapi-ccn.json`; the contract spec passes for all of them and the upstream contract spec still passes for the 22 upstream operations.
- **SC-002**: From this Mac, with the staging API token, one script creates a user, a webhook, a folder, a template preference and an account config through the API, reads each back, and reverts all of them, ending with the account in its initial state (S3 gate, FORK-PLAN.md §10).
- **SC-003**: `tools/list` on staging's `/mcp` lists the 8 fork tools and each is exercised once from Claude Code with a successful result.
- **SC-004**: No `/api/ccn/...` request in the specs or the gate produces a 500; every refused request carries a translated `error` string.
- **SC-005**: The set of upstream files edited in this stage is exactly `config/routes.rb`, `app/controllers/api/templates_controller.rb` and `app/controllers/mcp_controller.rb`, each with a one-line reason in `CCN-CHANGES.md`.
- **SC-006**: `CLAUDE.md` (operations directory) lists every operation available on staging, checked against `docs/openapi.json` + `docs/openapi-ccn.json` by hand at release.

## Assumptions

- All users of this instance are administrators (upstream OSS has a single role); role distinctions arrive with Stage 4 and will narrow these operations through `lib/ability.rb`, not through the controllers.
- Staging never sends e-mail: invitation and reset e-mails are exercised in specs with the test delivery method and on staging with `send_email: false` (invitation) or accepted as queued (reset).
- The ML field detector's model ships in the production image (the UI's "Detect fields" works on prod); in CI the detector is stubbed.
- Secret material (custom webhook header value, HMAC secret) is readable by an administrator through one explicit endpoint, as it is through the UI; the API token and MCP tokens are never readable.
- The fork OpenAPI file documents only fork additions; clients load it next to upstream's `docs/openapi.json`.
