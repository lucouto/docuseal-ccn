# Data model: P1 features — reminders, account logo, editor/viewer roles

No schema change (reminders read existing rows; the logo is an `ActiveStorage::Attachment`, whose tables
already exist; roles reuse the existing `role` column). This file fixes the request/response shapes, the
due-rule, the ability matrix and the bulk-list format.

## Common

- Auth: header `X-Auth-Token` (upstream API token), same as every other `/api/ccn/...` operation.
- Errors: `422 { "error": "<translated message>" }` for anything client-caused; `403` (upstream `CanCan::AccessDenied`
  JSON) when the caller's role lacks the permission; `404` for a missing or foreign record.

## Reminders — `Ccn::Reminders`

```ruby
DURATIONS = {
  'one_hour' => 1.hour, 'two_hours' => 2.hours, 'four_hours' => 4.hours,
  'twelve_hours' => 12.hours, 'twenty_four_hours' => 24.hours,
  # … the remaining AccountConfigs::REMINDER_DURATIONS keys, 16 total
  'thirty_days' => 30.days,
}
```
A spec asserts `DURATIONS.keys == AccountConfigs::REMINDER_DURATIONS.keys` (research D2) so an upstream
rename breaks CI, not production.

**Due rule** (`Ccn::Reminders.due(account, now: Time.current)`):

```
stage k (1..3) is due for submitter s when:
  account.submitter_reminders["#{stage_name(k)}_duration"] is set              # first/second/third
  s.completed_at.nil? && s.declined_at.nil?
  s.submission.archived_at.nil? && !s.submission.expired?
  s.submission.template && s.submission.template.archived_at.nil?
  s.sent_at.present?
  s.email.present?
  s.preferences['send_email'] != false
  !Submitters.email_bounced_recently?(s.email)
  events_sent(s) == k - 1                                                       # exactly the next stage
  now >= s.sent_at + DURATIONS[duration_k]
  now <= s.sent_at + DURATIONS[duration_k] + 7.days                             # else: expired, skipped
```
Result row: `{ submitter_id, submission_id, email, stage, due_at, name }`. Oldest `sent_at` first.

**Run** (`Ccn::Reminders.run(account:, now: Time.current, dry_run: false)`):

```json
{ "sent": 1, "skipped": { "no_email_delivery_configured": 3 }, "locked": false, "disabled": false }
```
`dry_run: true` computes `due` and reports the same counters without sending or writing events. When
`!Accounts.can_send_emails?(account)` every due signer is counted under `no_email_delivery_configured` and
`sent` stays 0 — no event is written for an e-mail that was not sent (SC-002).

| Operation | Input | Rules |
|-----------|-------|-------|
| `GET /api/ccn/reminders/due` | — | admins only (`authorize!(:manage, current_account)`); lists signers due now with their stage; no reason exposed for signers *not* due (privacy, FR requirement) |
| `POST /api/ccn/reminders/run` | `dry_run` (default false) | admins only; runs `Ccn::Reminders.run`; acquires the Redis lock (`ccn:reminders:lock`, `nx`, `ex 840`) — a concurrent call returns `locked: true` immediately, sends nothing |

Mailer (`CcnSubmitterReminderMailer#reminder_email(submitter)`): subject/body from, in order, the
template's `invitation_reminder_email_subject/body` preference, then the account's
`submitter_invitation_reminder_email` config, then `AccountConfig::DEFAULT_VALUES` (= the invitation texts);
`ReplaceEmailVariables`, `build_submitter_reply_to`, `maybe_set_custom_domain`, `from_address_for_submitter`,
`Submitters::ValidateSending.call(submitter, mail)` before delivery — the same rules the invitation job
applies. One `SubmissionEvent(event_type: 'send_reminder_email', submitter_id:)` per successful delivery,
written immediately after `deliver_now!`.

## Account logo — `Ccn::AccountLogo`

```ruby
module Ccn::AccountLogo
  extend ActiveSupport::Concern
  included do
    has_one_attached :logo
    validate :ccn_logo_format
  end
end
```
Accepted: `image/png`, `image/jpeg`, `image/webp` by `Marcel::MimeType.for(io)` (magic bytes, read with no
filename hint), and the declared `content_type` must not *contradict* them — a declared type naming a
different type is refused, while a generic one (blank, `application/octet-stream`) is taken at its bytes,
because some file managers send that for a perfectly good PNG. ≤ 2 MB; SVG refused unconditionally (it reads
as `application/xml` whatever the browser claims, which is what stops an SVG renamed `.png`).

| Operation | Input | Rules |
|-----------|-------|-------|
| `GET /api/ccn/account_logo` | — | `{ "url", "filename", "content_type", "byte_size" }`, 404 when no logo attached |
| `PUT /api/ccn/account_logo` | `file` (base64, data URI, or https URL — the same shapes `Ccn::DocumentParams` already accepts for ingestion) | validates type/size/magic bytes; replaces any existing logo; returns the same shape as `GET` |
| `DELETE /api/ccn/account_logo` | — | detaches; `{ "deleted": true }` |

UI (`CcnAccountLogosController`, multipart form in `personalization_settings/_logo_form`): `create` (upload),
`destroy` (remove); `authorize!(:manage, current_account)`.

Rendering: `shared/_ccn_brand_logo` renders `image_tag(url_for(account.logo))` when
`account.logo.attached?`, else `render 'shared/logo'` (today's DocuSeal mark) — used by
`submit_form/_docuseal_logo`, `start_form/_docuseal_logo`, and (as `shared/_ccn_mailer_logo`, an absolute-URL
variant for e-mail clients) `layouts/mailer.html.erb`. The attribution partials (`shared/_attribution`,
`shared/_email_attribution`) are **never edited** — reading them is how FR-007 is verified, not a rule enforced
by this code.

## User role — `Ccn::LastAdminGuard`, `lib/ability.rb`

```ruby
User::ROLES = %w[admin editor viewer].freeze   # ADMIN_ROLE = 'admin' unchanged
```

**Ability matrix** (research D9; `integration`/`superadmin` keep today's rules):

| Resource | admin | editor | viewer |
|----------|-------|--------|--------|
| Template, TemplateFolder | manage | create/read/update/destroy | read |
| Submission, Submitter | manage | manage (account-scoped) | read |
| User | manage | read (list), manage self *minus* `:create` | read (list), manage self *minus* `:create` |
| Account, AccountConfig, WebhookUrl | manage | — | — |
| own UserConfig/EncryptedUserConfig/AccessToken/McpToken/`:mcp` | manage | manage | manage |

`manage self` rather than `update self` because `ProfileController` asks for `manage` on the user themselves.
`:create` is then taken back from the two non-admin roles, because `UsersController` reads `can?(:create, user)`
as "may administer users": it is what lets a *blank* `archived_at` through (an unarchive) and what shows the
"Add user" button. It does not gate archiving as such — `archived_at` is in the controller's permitted list —
so a non-admin can still archive themselves. Left as it is: it locks them out, an administrator undoes it,
and no privilege is gained. Archiving or editing *somebody else* is refused, which is the rule that matters.

Effect on `/api/ccn/...` (no controller change — `authorize!` already reads these rules): `users`,
`webhooks`, `account_configs` → 403 for editor and viewer; `template_folders` → editor yes, viewer **403 on every action, listing included** (one `authorize!(:manage, TemplateFolder)` covers the whole namespace; a viewer still sees each template's folder through `GET /templates`);
`Api::CcnTemplate*` (versions, detect_fields) and template preferences → editor yes (`:update`), viewer
read-only (`:read`); ingestion endpoints (`/api/templates/*`, `/api/submissions/*`) → editor yes, viewer no
(create/update actions require `:create`/`:update`, which viewer lacks).

`Ccn::LastAdminGuard` (validation on `User`, included next to the `ROLES` line): refuses a save that would
leave the account without an active (`archived_at IS NULL`), non-integration `role: 'admin'` user — triggered
by a role change away from `admin` or by setting `archived_at`. Error key `ccn_last_admin_required` (en/fr),
surfaces as `422 { "error": … }` in `/api/ccn/users` and MCP `manage_users` (both already rescue
`ActiveRecord::RecordInvalid`); in the UI, `Ccn::UsersControllerGuard` adds
`rescue_from ActiveRecord::RecordInvalid` → `redirect_back(alert: …)` because upstream's `UsersController#destroy`
calls `update!` directly.

| Operation | Input | Rules |
|-----------|-------|-------|
| `POST /api/ccn/users`, `PUT /api/ccn/users/{id}` | `role` ∈ `User::ROLES` | unchanged validation, now accepts `editor`/`viewer`; last-admin guard applies to `PUT`/`DELETE` |
| `DELETE /api/ccn/users/{id}` | — | last-admin guard applies |

## Bulk list (optional, US4) — `Ccn::SubmissionsLists`

Input: CSV (stdlib `CSV`) or XLSX (`RubyXL::Parser`, first sheet only), header row required, ≤ 500 data rows.

Columns: `email` (required — file refused without it), `name`, `phone`; one prefillable-field column per
field, named by the field itself when the template has one role, or `RoleName: field` when it has several;
role columns for a multi-role template follow the same `RoleName: email` / `RoleName: name` pattern.

```json
{ "columns": ["email", "name", "Signer: Amount"], "rows_count": 3,
  "preview": [{ "email": "a@x.org", "name": "A", "Signer: Amount": "100" }],
  "errors": []
}
```
A malformed row (bad e-mail, missing required column value) is reported as `{ "line": 4, "error": "…" }` and
the whole file is refused — nothing is sent (FR-010). On confirm, one `Submissions.create_from_submitters`
call per row (`send_email` as chosen on the form), same code path `POST /api/submissions` uses.

## MCP

No new MCP tool for reminders (research D6 — running a send from a model transcript is not wanted; the
existing `account_config` tool already sets `submitter_reminders` durations). No new MCP tool for the logo or
roles either — `manage_users` already accepts `role: editor|viewer` once `User::ROLES` changes, and the logo
is a settings-page/e-mail concern, not something Claude Code needs to drive by MCP for this stage.
