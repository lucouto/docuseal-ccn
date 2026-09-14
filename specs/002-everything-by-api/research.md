# Research: Everything else by API

All facts from the fork at `83470548` (upstream 3.2.4) unless noted. Inventory taken 2026-09-14 from the UI
controllers named in FORK-PLAN.md §3.2 (routes, permitted params, guards, side effects).

## D1 — Controller and route layout

**Decision**: flat controllers `Api::CcnUsersController`, `Api::CcnWebhooksController`,
`Api::CcnAccountConfigsController`, `Api::CcnTemplateFoldersController`, `Api::CcnTemplateVersionsController`,
`Api::CcnTemplateDetectFieldsController` in `app/controllers/api/`, mounted with one `scope 'ccn'` block inside
the existing `namespace :api` of `config/routes.rb`, each `resources` given `controller:` and `as: 'ccn_…'`.

**Rationale**: an `Api::Ccn` module would shadow `::Ccn` inside the controllers (plan 001, structure
decision); `resources :users` without `as:` would define `api_user` a second time (upstream already has
`resource :user`). Route helpers become `api_ccn_users_path`, `api_ccn_webhook_path`, …

**Alternatives**: a Rails engine (`ccn_api`) — heavier, and the upstream API base controller is what we want to
inherit (auth, pagination, error table).

## D2 — Authorization

**Decision**: no `load_and_authorize_resource`; every action loads through the account
(`current_account.users.find`, `current_account.webhook_urls.find`, `Template.accessible_by(current_ability)`)
and calls `authorize!` explicitly (`:manage` on `User` / `WebhookUrl` / `AccountConfig` / `TemplateFolder`,
`:update` on the template for preferences, versions and detection). `check_authorization` in
`Api::ApiBaseController` then guarantees no action ships without a check.

**Rationale**: CanCan derives the resource from the controller name; in a controller not named after it the
symbol becomes a *parent* (`params[:x_id]`, `:show` on the class) — the Stage 2 `parent: false` lesson. Explicit
`authorize!` is also what Stage 4 will narrow when roles arrive (`lib/ability.rb`, not the controllers).
Foreign records are 404 through the account scope (`find` raises `RecordNotFound`, handled as upstream does).

## D3 — One service module per resource, shared by REST and MCP

**Decision**: `lib/ccn/manage_users.rb`, `lib/ccn/manage_webhooks.rb`, `lib/ccn/manage_account_configs.rb`,
`lib/ccn/template_preferences.rb`, `lib/ccn/manage_folders.rb`, `lib/ccn/template_version_restore.rb`,
`lib/ccn/detect_template_fields.rb` — `module_function` modules taking plain hashes (indifferent access),
raising `Ccn::AdminInvalid` (< StandardError, translated message) for anything the client caused, returning
serializable hashes. Controllers are thin; MCP tool controllers call the same functions.

**Rationale**: FR-009 wants MCP and REST to behave identically; the Stage 2 rescue table
(`Ccn::IngestionErrors`) already shows the pattern. Names avoid clashing with upstream modules referenced from
inside `Ccn` (`::TemplateFolders`, `::TemplateVersions`, `::Users` exist — hence `ManageFolders`,
`TemplateVersionRestore`, `ManageUsers`).

## D4 — Account configuration keys and value types

**Decision**: allow-list = `AccountConfigsController::ALLOWED_KEYS` (19 keys) ∪
`PersonalizationSettingsController::ALLOWED_KEYS` (6 keys + `policy_links` on-premises) ∪ `bcc_emails`,
`submitter_reminders`. Every key carries a type in `Ccn::ManageAccountConfigs::KEYS`:

| type | keys |
|------|------|
| boolean | `allow_typed_signature`, `force_mfa`, `allow_to_resubmit`, `allow_to_decline`, `allow_to_delegate`, `form_prefill_signature`, `form_with_confetti`, `download_links_auth`, `force_sso_auth`, `flatten_result_pdf`, `enforce_signing_order`, `with_file_links`, `with_signature_id`, `combine_pdf_result_key`, `require_signing_reason`, `enable_mcp`, `download_links_expire` (a boolean upstream: `lib/accounts.rb` and the blob proxy compare it to `false`; the UI select is only the toggle's presentation) |
| string | `esigning_preference` (`single` / `multiple`... as the UI select), `document_filename_format`, `bcc_emails`, `policy_links` (markdown) |
| object | `submitter_invitation_email`, `submitter_invitation_reminder_email`, `submitter_documents_copy_email`, `submitter_completed_email` (`subject`, `body`, plus `reply_to`, `attach_audit_log`, `attach_documents`, `bcc_recipients`, `enabled` where the UI form has them), `form_completed_button` (`title`, `url`), `form_completed_message` (`title`, `body`), `submitter_reminders` (`first_duration`, `second_duration`, `third_duration` ∈ `AccountConfigs::REMINDER_DURATIONS.keys`) |

Coercions as the UI: `'1'/'0'/'true'/'false'` → boolean for boolean keys; object members not in the member list
→ 422; blank members removed; a blank value (`null`, `''`, `{}`) on `PUT` behaves like `DELETE` (the UI destroys
the row). `default` in the read response comes from `AccountConfig::DEFAULT_VALUES` (five e-mail keys, evaluated
in the request locale). `EncryptedConfig::CONFIG_KEYS` are not in the table → "unknown setting" like any other
key; they are never looked up.

**Rationale**: the model has no allow-list (`account_config.rb`); the three UI controllers each hold one;
typing them here is what makes 422s precise and keeps `EncryptedConfig` out by construction.

## D5 — Webhook secrets

**Decision**: `secret` (custom header, `{key => value}`, one entry) is write-only through `PUT`
(`secret: {}` clears); `hmac_secret` is never written by the client. Both are revealed by one explicit
`GET /api/ccn/webhooks/{id}/secret` (mirrors `WebhookSecretController#show` and the UI's signing-secret display);
list/show responses carry `secret_key` (header name or null) only.

**Rationale**: an integration (n8n) needs the HMAC secret once to verify signatures; putting it in every list
response would spread it into logs and transcripts.

## D6 — `preferences` on `PUT /api/templates/{id}`

**Decision**: one hook in `Api::TemplatesController#update` (upstream file, registered in `CCN-CHANGES.md`):
`Ccn::TemplatePreferences.apply!(@template, ccn_preferences_params, current_account) if …present?`, placed with
the other non-attribute params (`folder_name`, `roles`, `archived`) before `@template.update!`. Allow-list copied
from `TemplatesPreferencesController#template_params` (the 30 scalar keys + `completed_message{title,body}`,
`submitters[{uuid,request_email_subject,request_email_body}]`, `link_form_fields[]`); `default_expire_at`
parsed in `current_account.timezone` and stored UTC; `'true'/'false'` → boolean; `null` deletes the key; unknown
key → 422 `ccn_unknown_preference`.

**Rationale**: FORK-PLAN §3.2 asks for this exact extension; the response and the `template.updated` webhook
stay upstream's. A separate `/api/ccn/templates/{id}/preferences` would duplicate the operation clients already
use for `name`/`folder_name`/`roles`.

## D7 — Template versions and restore

**Decision**: `GET`/`POST` reuse `TemplateVersions.serialize` / `find_or_create_for`. `restore`: (1) refuse
(422 `ccn_version_documents_missing`) when `version.data['schema']` references an `attachment_uuid` the
template's `documents_attachments` no longer has; (2) `TemplateVersions.find_or_create_for(template, author:
current_user)` (the pre-restore snapshot); (3) assign `TemplateVersions::DATA_FIELDS` from `version.data`;
`save!`; `template.updated` webhook + search reindex. Dynamic documents (`dynamic_documents`) are not restored
(P2 feature, `NotSupportedYet` when the version has any).

**Rationale**: the OSS UI has no server-side restore (the builder loads a version and saves); a server-side
restore must not point fields at documents that are gone.

## D8 — Field detection

**Decision**: `POST /api/ccn/templates/{id}/detect_fields` runs `Templates::DetectFields.call(io, attachment:,
page_number:)` synchronously per selected document (all schema documents, or `attachment_uuid`; `page` 1-based
optional), collects the yielded `(attachment_uuid, page, fields)` triples, returns
`{ documents: [{ attachment_uuid, pages: [{ page, fields: [...] }] }] }`. Cap: 30 pages per request (422 beyond).
`apply: true` appends candidates as fields of the first submitter (uuid generated, `required: true`), skipping a
candidate whose name and area match an existing field; saves; `template.updated` webhook.

**Rationale**: the UI streams SSE for progressive display; an API client wants one JSON. The detector needs the
ONNX model (`Templates::ImageToFields`), present in the production image (the UI's button works on prod) —
stubbed in CI (`allow(Templates::DetectFields).to receive(:call)` yielding fixtures).

## D9 — Not implemented, and why

| §3.2 row | Decision |
|----------|----------|
| Submissions unarchive | already available upstream: `PUT /api/submissions/{id}` with `archived: false` (`assign_submission_attrs`, `api/submissions_controller.rb:140-144`) → documented in the cheat sheet, no code |
| Submitters resubmit | `SubmittersResubmitController` is a signer self-service (guard `submitter.email == current_user.email`, completed < 1 month) — no administrative meaning; resend already exists (`PUT /api/submitters/{id}` + `send_email: true`, upstream) |
| Template sharing / access | `Templates.maybe_assign_access` is an OSS no-op; meaningful only with Stage 4 roles |
| Users CSV export | `Users.generate_csv` — `GET /api/ccn/users?format=csv`? Not needed: the JSON list is the export |
| Folder delete that moves templates | Pro-only; the fork archives empty folders only (`DELETE` 422 otherwise); moving templates is `PUT /api/templates/{id}` `folder_name` |

## D10 — MCP tools

**Decision**: eight `Mcp::Ccn*Controller` classes under `app/controllers/mcp/`, each with `SCHEMA` and `call`,
registered in `McpController::TOOL_CONTROLLERS` (upstream file, one hash entry per tool, in `CCN-CHANGES.md`).
Tools: `create_template_from_documents` (pdf/docx/html; `documents[]` as in REST, `merge_documents`),
`update_template_documents`, `merge_templates`, `create_submission_from_documents` (one submission,
`submitters[]`), `manage_users` (`action` ∈ list/invite/update/archive/reset_password), `manage_webhooks`
(`action` ∈ list/create/update/delete/test/events), `account_config` (`action` ∈ list/get/set/reset),
`set_template_preferences`. Errors: `Ccn::AdminInvalid`, `Ccn::DocumentParams::Invalid`, `Ccn::NotSupportedYet`,
`Ccn::Gotenberg::Error`, `ActiveRecord::RecordInvalid` → `render_tool_error(message)`; the base controller's
`AccessDenied`/`RecordNotFound` handling is upstream's. Ingestion tools reuse the Stage 2 modules
(`Ccn::CreateTemplateFromDocuments`, `Ccn::UpdateTemplateDocuments`, `Ccn::MergeTemplates`,
`Ccn::CreateSubmissionFromDocuments` + the detach/discard sequence, extracted from the REST controller into
`Ccn::CreateSubmissionFromDocuments.create!(user:, params:, format:)` so both surfaces share it).

**Rationale**: MCP has no upstream tests; a request spec `spec/requests/ccn_mcp_spec.rb` creates an `McpToken`
(`user.mcp_tokens.create!` → `token` attribute), sets `AccountConfig enable_mcp = true`, and exercises
`tools/list` and one `tools/call` per tool. Authentication and `verify_mcp_enabled!` are untouched.

## D11 — Fork OpenAPI reference and contract spec

**Decision**: `docs/openapi-ccn.json`, OpenAPI 3.1.0, `info.title` "DocuSeal CCN API (fork additions)",
`servers` = `https://docuseal.cheminneuf.community/api` and the staging host, `components.securitySchemes.AuthToken`
identical to upstream, `tags` `["Users", "Webhooks", "Account", "Templates"]`, inlined schemas with `examples`,
one path per operation under `/ccn/...`, plus `/templates/{id}` with only the `put` operation redocumented
(request body = upstream's + `preferences`), marked `x-ccn-extends: "docs/openapi.json#/paths/~1templates~1{id}/put"`.
`spec/requests/ccn_openapi_contract_spec.rb` reuses `spec/support/openapi_contract.rb` with `SPEC_PATH`
parameterised (`OpenapiContract.load(path)`), asserts every operation routable and validates each 200 body.

**Rationale**: constitution II names this file; a merged 556 KB copy of upstream's spec would drift on every
rebase.

## D12 — E-mail side effects on staging

**Decision**: `POST /api/ccn/users` sends the invitation through `UserMailer.invitation_email(user, invited_by:
current_user).deliver_later!` unless `send_email: false`; `reset_password` calls
`user.send_reset_password_instructions` as the UI does. Staging has no SMTP: the S3 gate invites with
`send_email: false` and treats reset's 200 as "queued" (Devise delivers through the app's default delivery,
`raise_delivery_errors = false` upstream).

## Verified upstream facts used here

- `Api::ApiBaseController`: `authenticate_user!` via `X-Auth-Token` SHA256 → `User.joins(:access_token).active`;
  `check_authorization`; `paginate(relation, field: :id)` (`limit` ≤ 100, `after`/`before`); `CanCan::AccessDenied`
  → 403 JSON, `Params::BaseValidator::InvalidParameterError` and `JSON::ParserError` → 422.
- `lib/ability.rb`: `manage` on `User`, `AccountConfig`, `WebhookUrl`, `TemplateFolder`, `Account` scoped by
  `account_id`; templates through `Abilities::TemplateConditions`.
- `User::ROLES = ['admin']`; `'integration'` users are filtered from the default list (`users_controller.rb:12-16`).
- `WebhookUrl`: `events` JSON array, default the four `form.*`; `secret` JSON hash; `hmac_secret` generated
  `before_validation`; `encrypts :url, :secret, :hmac_secret`; `EVENTS` = 11 names.
- `WebhookEvent` (`uuid`, `event_type`, `record_type`, `record_id`, `status` ∈ success/error) `has_many
  :webhook_attempts` (`attempt`, `response_status_code`, `response_body`, `created_at`); resend =
  `WebhookUrls::EVENT_TYPE_TO_JOB_CLASS[event_type].perform_async(EVENT_TYPE_ID_KEYS[...] => record_id,
  'webhook_url_id', 'event_uuid', 'attempt' => SendWebhookRequest::MANUAL_ATTEMPT, 'last_status' => 0)`; test =
  `SendTestWebhookRequestJob.perform_async('submitter_id', 'event_uuid', 'webhook_url_id')` with the account's
  last completed submitter.
- `TemplateFolders.find_or_create_by_name(author, name)`: blank/`Default` → default folder; `"Parent / Child"`
  two levels; `TemplateFolder#full_name`, `#default?`; `Template.active.where(folder_id:)` counts.
- `TemplateVersions`: `SERIALIZE_PARAMS`, `DATA_FIELDS`, `find_or_create_for` (sha1-idempotent), `serialize`.
- `Templates::DetectFields.call(io, attachment:, page_number:)` yields `(attachment_uuid, page, fields)`.
- `McpController::TOOL_CONTROLLERS` / `TOOLS` (derived from each `SCHEMA`); `Mcp::McpBaseController`
  (`mcp_params`, `render_tool_result`, `render_tool_error`, Bearer `McpToken` auth, `enable_mcp` gate).
- `docs/openapi.json`: 3.1.0, no `components.schemas`, `examples` arrays on request properties, single `example`
  on responses, `security: [{AuthToken: []}]` per operation; `spec/support/openapi_contract.rb` validates
  `oneOf/anyOf/allOf`, type arrays, `required`, `properties`, `items` (first 20).
