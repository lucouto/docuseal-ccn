# Data model: Everything else by API

No schema change. This file fixes the request/response shapes and the allow-lists the services enforce.

## Common

- Auth: header `X-Auth-Token` (upstream API token). All `/api/ccn/...` responses are JSON.
- Lists: `{ "data": [...], "pagination": { "count", "next", "prev" } }` via `Api::ApiBaseController#paginate`
  (`limit` ≤ 100, `after`, `before`), newest first.
- Errors: `422 { "error": "<translated message>" }` for anything client-caused (`Ccn::AdminInvalid`,
  `ActiveRecord::RecordInvalid` → `full_messages.to_sentence`); `404` for a missing or foreign record (upstream's
  `RecordNotFound` handling); `403` upstream `CanCan::AccessDenied` JSON; `401` upstream.
- Booleans in requests accept `true/false`, `"true"/"false"`, `"1"/"0"` (`Ccn::DocumentParams.boolean`).

## Users — `Ccn::ManageUsers`

Serialized user (`Ccn::ManageUsers.serialize`):

```json
{ "id": 3, "email": "a@x.org", "first_name": "A", "last_name": "B", "role": "admin",
  "archived_at": null, "otp_required_for_login": false,
  "current_sign_in_at": "2026-09-14T08:00:00.000Z", "last_sign_in_at": null,
  "created_at": "…", "updated_at": "…" }
```

Never serialized: `uuid` (impersonation handle), `encrypted_password`, tokens, `sign_in_count`, IPs.

| Operation | Input | Rules |
|-----------|-------|-------|
| `GET /api/ccn/users` | `status` ∈ `active` (default: `archived_at IS NULL AND role != 'integration'`), `archived`, `integration`; `limit/after/before` | `authorize!(:manage, User)` |
| `POST /api/ccn/users` | `email` (required, `User::EMAIL_REGEXP`), `first_name`, `last_name`, `password` (default `SecureRandom.hex`), `role` (∈ `User::ROLES`, else default), `otp_required_for_login`, `send_email` (default true) | existing active e-mail anywhere → 422 `ccn_user_exists`; archived e-mail in this account → reactivated (attributes applied); side effect `UserMailer.invitation_email(user, invited_by: actor).deliver_later!` when `send_email` |
| `GET /api/ccn/users/{id}` | — | account-scoped |
| `PUT /api/ccn/users/{id}` | `email first_name last_name password archived_at otp_required_for_login role` | self: `role`, `otp_required_for_login` and `archived_at` refused (422 `ccn_self_change_refused`); `password` applied only when present; e-mail change → `SendConfirmationInstructionsJob` when `pending_reconfirmation?` |
| `DELETE /api/ccn/users/{id}` | — | self → 422; sets `archived_at = now`; returns the user |
| `POST /api/ccn/users/{id}/reset_password` | — | archived → 422; `reset_password_sent_at` within 10 min → 422 `ccn_reset_already_sent`; `user.send_reset_password_instructions`; `{ "sent": true }` |

## Webhooks — `Ccn::ManageWebhooks`

Serialized webhook:

```json
{ "id": 2, "url": "https://n8n.example/hook", "events": ["form.completed"], "secret_key": "X-Token",
  "created_at": "…", "updated_at": "…" }
```

Secret reveal (`GET /api/ccn/webhooks/{id}/secret`): `{ "secret": { "X-Token": "…" }, "hmac_secret": "…" }`.

Serialized delivery (event):

```json
{ "uuid": "…", "event_type": "form.completed", "record_type": "Submitter", "record_id": 12, "status": "error",
  "created_at": "…", "attempts": [{ "attempt": 1, "response_status_code": 500, "created_at": "…" }] }
```

| Operation | Input | Rules |
|-----------|-------|-------|
| `GET /api/ccn/webhooks` | pagination | `authorize!(:manage, WebhookUrl)` |
| `POST /api/ccn/webhooks` | `url` (required, `http`/`https`), `events[]` (⊆ `WebhookUrl::EVENTS`, default `%w[form.viewed form.started form.completed form.declined]`), `secret {key,value}` | unknown event → 422 `ccn_unknown_webhook_event` (names it); bad url → 422 `ccn_invalid_url` |
| `GET /api/ccn/webhooks/{id}` | — | |
| `PUT /api/ccn/webhooks/{id}` | `url`, `events[]`, `secret` (`{}` clears) | same validations; `secret` replaced whole |
| `DELETE /api/ccn/webhooks/{id}` | — | `destroy!`; returns `{ id, deleted: true }` |
| `GET /api/ccn/webhooks/{id}/secret` | — | reveal |
| `GET /api/ccn/webhooks/{id}/events` | `status` ∈ `success`, `error`; pagination | `webhook_events` newest first, attempts preloaded |
| `POST /api/ccn/webhooks/{id}/events/{uuid}/resend` | — | `WebhookUrls::EVENT_TYPE_TO_JOB_CLASS[event_type].perform_async(id_key => record_id, 'webhook_url_id', 'event_uuid', 'attempt' => SendWebhookRequest::MANUAL_ATTEMPT, 'last_status' => 0)`; `{ "queued": true }` |
| `POST /api/ccn/webhooks/{id}/test` | — | last completed submitter of the account (`Submitter.where(account:).where.not(completed_at: nil).order(:id).last`) else 422 `ccn_no_completed_submitter`; `SendTestWebhookRequestJob.perform_async('submitter_id', 'event_uuid' => SecureRandom.uuid, 'webhook_url_id')`; `{ "queued": true, "event_uuid" }` |

## Account configs — `Ccn::ManageAccountConfigs`

`KEYS` table (key → `{ type:, members: }`), from research D4. Serialized:

```json
{ "key": "submitter_invitation_email", "type": "object", "value": null,
  "default": { "subject": "You are invited to submit a form", "body": "…" } }
```

| Operation | Rules |
|-----------|-------|
| `GET /api/ccn/account_configs` | every key of `KEYS`, `value` from the stored row or `null`, `default` from `AccountConfig::DEFAULT_VALUES` (evaluated) or absent; `authorize!(:manage, AccountConfig)` |
| `GET /api/ccn/account_configs/{key}` | unknown key → 422 `ccn_unknown_setting` |
| `PUT /api/ccn/account_configs/{key}` body `{ "value": … }` | boolean: coerce `'1'/'0'/'true'/'false'`, else 422 `ccn_invalid_setting_value`; string: must be String; object: Hash, members ⊆ `members`, blank members removed, `submitter_reminders` members ∈ `AccountConfigs::REMINDER_DURATIONS.keys`; blank value → delete row; else `find_or_initialize_by(account:, key:)` + `update!(value:)`; returns the serialized config |
| `DELETE /api/ccn/account_configs/{key}` | deletes the row if any; returns the serialized config (value null) |

Object members:

| key | members |
|-----|---------|
| `submitter_invitation_email`, `submitter_invitation_reminder_email` | `subject body reply_to` |
| `submitter_completed_email` | `subject body attach_audit_log attach_documents` |
| `submitter_documents_copy_email` | `subject body reply_to attach_audit_log attach_documents bcc_recipients enabled` |
| `form_completed_button` | `title url` |
| `form_completed_message` | `title body` |
| `submitter_reminders` | `first_duration second_duration third_duration` |

## Template preferences — `Ccn::TemplatePreferences`

`KEYS` (scalar) = `bcc_completed request_email_subject request_email_body invitation_view_email_subject
invitation_view_email_body invitation_reminder_email_subject invitation_reminder_email_body
documents_copy_email_subject documents_copy_email_body documents_copy_email_enabled
documents_copy_email_attach_audit documents_copy_email_attach_documents documents_copy_email_reply_to
completed_notification_email_attach_documents completed_redirect_url validate_unique_submitters
require_all_submitters submitters_order require_phone_2fa require_email_2fa default_expire_at_duration
shared_link_2fa default_expire_at request_email_enabled completed_notification_email_subject
completed_notification_email_body completed_notification_email_enabled completed_notification_email_attach_audit`;
nested: `completed_message {title body}`, `submitters [{uuid request_email_subject request_email_body}]`,
`link_form_fields []`.

`apply!(template, preferences, account)`: unknown key → 422 `ccn_unknown_preference`; `null` → `delete(key)`;
`'true'/'false'` → boolean; `default_expire_at` → `Time.zone (account.timezone).parse(value).utc.iso8601`... (the
UI: `ActiveSupport::TimeZone[account.timezone].parse(value).utc`); blank String/Hash removed (as the UI's
`reject`); result merged into `template.preferences`. The upstream `update` then saves and fires
`template.updated`.

## Folders — `Ccn::ManageFolders`

Serialized: `{ "id", "name", "full_name", "parent_folder_id", "archived_at", "templates_count", "created_at", "updated_at" }`
(`templates_count` = `Template.active.where(folder_id:).count`).

| Operation | Rules |
|-----------|-------|
| `GET /api/ccn/template_folders` | `current_account.template_folders.active`, pagination; `authorize!(:manage, TemplateFolder)` |
| `POST /api/ccn/template_folders` body `{ "name": "Parent / Child" }` | > 2 levels → 422 `ccn_folder_depth`; `TemplateFolders.find_or_create_by_name(current_user, name)`; returns the folder (200 whether created or found) |
| `PUT /api/ccn/template_folders/{id}` body `{ "name" }` | default folder → 422 `ccn_default_folder_immutable`; `update!(name:)` |
| `DELETE /api/ccn/template_folders/{id}` | default → 422; active templates or active subfolders → 422 `ccn_folder_not_empty`; `update!(archived_at: now)` |

## Versions — `Ccn::TemplateVersionRestore`

| Operation | Rules |
|-----------|-------|
| `GET /api/ccn/templates/{id}/versions` | `template.template_versions.order(id: :desc)` as `TemplateVersions::SERIALIZE_PARAMS`; `authorize!(:read, template)` |
| `POST /api/ccn/templates/{id}/versions` | `TemplateVersions.find_or_create_for(template, author: current_user)`; `authorize!(:update, template)` |
| `GET /api/ccn/templates/{id}/versions/{version_id}` | `TemplateVersions.serialize(version)` |
| `POST /api/ccn/templates/{id}/versions/{version_id}/restore` | `version.data['dynamic_documents'].present?` → `NotSupportedYet`; missing attachment uuid → 422 `ccn_version_documents_missing`; pre-snapshot; assign `DATA_FIELDS`; `save!`; `WebhookUrls.enqueue_events(template, 'template.updated')`; `SearchEntries.enqueue_reindex`; returns `Templates::SerializeForApi.call(template)` |

## Field detection — `Ccn::DetectTemplateFields`

Request: `{ "attachment_uuid": "…" (optional), "page": 1 (optional, 1-based), "apply": false }`.
Response: `{ "documents": [{ "attachment_uuid", "pages": [{ "page": 1, "fields": [{ "type", "name", "areas": [{ "x", "y", "w", "h", "page", "attachment_uuid" }] }] }] }], "applied": 0 }`.
Rules: no schema document → 422 `ccn_no_documents`; total pages > 30 → 422 `ccn_too_many_pages`;
`page` beyond the document → 422 `ccn_invalid_page`; a detector failure (corrupt/encrypted PDF, bad image) → 422;
`apply: true` → each candidate becomes `{ uuid, name: '', type, required (as detected), submitter_uuid: first
submitter, areas }` — the detector yields no name, so the fields are unnamed like the editor's own detection and
are renamed through `PUT /api/templates/{id}` `fields[]` — unless an existing field has an area on the same page
overlapping it (IoU > 0.5);
`template.save!`; `template.updated` webhook.

## MCP tool arguments (mirror the REST bodies)

| tool | arguments |
|------|-----------|
| `create_template_from_documents` | `format` (`pdf`/`docx`/`html`), `name`, `folder_name`, `external_id`, `documents[]` (`file` base64/URL or `html`, `name`, `fields[]`, `position`), `html`, `size`, `remove_tags`, `flatten` |
| `update_template_documents` | `template_id`, `documents[]` (`file`, `name`, `position`, `replace`, `remove`), `merge` |
| `merge_templates` | `template_ids[]`, `name`, `folder_name`, `roles[]` |
| `create_submission_from_documents` | `format`, `documents[]`, `submitters[]`, `send_email`, `message`, `order`, `merge_documents` |
| `manage_users` | `action` ∈ `list invite update archive reset_password`, `id`, `status`, user attributes, `send_email` |
| `manage_webhooks` | `action` ∈ `list create update delete test events`, `id`, `url`, `events[]`, `secret`, `status` |
| `account_config` | `action` ∈ `list get set reset`, `key`, `value` |
| `set_template_preferences` | `template_id`, `preferences {}` |

Tool results are the REST JSON as text content; failures are `isError: true` with the REST `error` message.
