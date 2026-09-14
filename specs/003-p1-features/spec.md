# Feature Specification: P1 features — reminders, account logo, editor/viewer roles

**Feature Branch**: `ccn` (spec directory `003-p1-features`)

**Created**: 2026-09-14

**Status**: Draft

**Input**: User description: "Stage 4 of FORK-PLAN.md — the P1 set: automated e-mail reminders to signers who have not completed their part, an account logo shown on the signing page and in e-mails next to the DocuSeal attribution, editor and viewer roles for account users, and — optional — a bulk send from a CSV/XLSX list in the UI. Luciano 2026-09-14: 'when finished, and if everything is ok, move to S4'."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Signers are reminded automatically (Priority: P1)

An administrator sets "first reminder in 1 day, second in 3 days, third in 7 days" in Settings → Notifications. From then on, every signer who received a signature request and has not signed, declined or been archived receives up to three reminder e-mails at those delays after the request was sent, each one visible in the submission's event log as "Reminder email sent to …". Nobody has to chase signers by hand any more.

**Why this priority**: it is the Pro feature CCN staff asked for first; the settings form, the e-mail template key, the event type, its icon and its translations already exist in the open-source build — only the sending is missing.

**Independent Test**: on staging, set the reminders to 1 hour / 2 hours / 4 hours, create a submission through the API with `send_email: true`, move the clock (or the submitter's `sent_at`) back two hours, run the reminders once through the API: the dry run lists the signer as due for reminder 1 and 2, the run sends exactly one (reminder 1), records one `send_reminder_email` event, and a second run right after sends nothing more.

**Acceptance Scenarios**:

1. **Given** an account with `submitter_reminders` `{ first_duration: 'twenty_four_hours', second_duration: 'three_days', third_duration: 'seven_days' }` and a signer sent 25 hours ago who has not completed, **When** the reminder run executes, **Then** one reminder e-mail is delivered to that signer with the account's reminder template (subject/body, variables replaced like the invitation), a `send_reminder_email` event is recorded for the signer, and the submission page shows "Reminder email sent to …" with the mail icon.
2. **Given** the same signer, **When** the run executes again before 3 days have passed, **Then** nothing is sent (idempotent: the number of reminders already sent decides the next stage); **When** it executes after 3 days, **Then** the second reminder is sent, and after 7 days the third; **Then** never a fourth.
3. **Given** a signer who has completed, declined, whose submission is archived or expired, whose template is archived, whose e-mail is blank or bounced in the last 24 hours, or whose submission was created with `send_email: false` for that signer, **When** the run executes, **Then** no reminder is sent to them and no event is recorded.
4. **Given** a submission whose template preferences set `invitation_reminder_email_subject`/`_body`, **When** a reminder is sent, **Then** the template's texts are used instead of the account's; **Given** neither is set, **Then** the default (the invitation texts, as `AccountConfig::DEFAULT_VALUES` defines) is used.
5. **Given** the account has no reminder durations configured, or `CCN_REMINDERS_ENABLED` is not `true` in the environment, **When** the scheduler ticks, **Then** nothing is sent and the run reports itself as disabled; the settings form still saves the durations.
6. **Given** a reminder that fell due more than 7 days ago (for example after the feature is enabled on an instance with an old backlog, or after a long outage), **When** the run executes, **Then** that stage is skipped, never sent late; **Given** more signers are due than the per-run cap, **Then** the run sends up to the cap (oldest first) and the rest wait for the next tick.
7. **Given** an administrator (or Claude Code), **When** `GET /api/ccn/reminders/due` is called, **Then** the signers due at this moment are listed with the stage each would receive and the reason others were skipped is not exposed (privacy: only due signers); **When** `POST /api/ccn/reminders/run` is called, **Then** one run executes immediately and the response counts sent/skipped; both require an administrator.
8. **Given** the Settings → Notifications page, **When** it is displayed, **Then** the "not available yet" banner is replaced by the reminder e-mail template form (subject, body, variables `{{template.name}}`, `{{submitter.link}}`, `{{account.name}}`), and the template's preferences page shows the "Signature request reminder email" collapse for the per-template override.

---

### User Story 2 - The account's logo on the signing page and in e-mails (Priority: P1)

An administrator uploads the community's logo in Settings → Personalization → Company logo. Signers then see that logo at the top of the signing page and in the signature request e-mails, while the "Powered by DocuSeal" attribution stays where it is.

**Why this priority**: signers are more likely to trust and open a request that carries the organisation's identity; the upload slot, the public-read rule for a blob named `logo` and the settings section already exist in the open-source build.

**Independent Test**: upload a PNG through the settings page (or `PUT /api/ccn/account_logo`), open a signing link on staging: the logo is displayed above the document name; the footer still reads "Powered by DocuSeal … · Source code"; remove the logo: the DocuSeal mark is back.

**Acceptance Scenarios**:

1. **Given** an administrator, **When** a PNG, JPEG or WebP file of at most 2 MB is uploaded in Settings → Personalization → Company logo, **Then** it is stored as the account's logo, previewed on the page, and can be removed there; any other type or a bigger file is refused with a translated message and nothing is stored.
2. **Given** an account with a logo, **When** a signer opens `/s/:slug` (signing page, including its completed, declined and expired variants) or `/d/:slug` (start form), **Then** the logo is shown in the header instead of the DocuSeal mark, and the DocuSeal attribution ("Powered by DocuSeal — open source documents software · Source code") remains in the footer unchanged (AGPL §7(b)).
3. **Given** an account with a logo, **When** a signature request, reminder, completed or documents-copy e-mail is sent, **Then** the e-mail shows the logo (as a hosted image) above the text and keeps the "Sent using DocuSeal" attribution at the bottom; **Given** no logo, **Then** the e-mails are unchanged.
4. **Given** an administrator, **When** `GET /api/ccn/account_logo` is called, **Then** the logo's public URL, filename, content type and size are returned (404 when none); `PUT /api/ccn/account_logo` with `file` (base64, data URI or https URL, as the ingestion endpoints accept) replaces it with the same validation; `DELETE /api/ccn/account_logo` removes it.
5. **Given** the application's own pages (dashboard, settings), **When** displayed, **Then** they still show the DocuSeal mark and name (the logo is for signers and e-mails; the product identity stays as upstream ships it).

---

### User Story 3 - Editor and viewer roles (Priority: P1)

An administrator invites a colleague as **editor**: they can create and edit templates, send documents and follow submissions, but cannot change account settings, users, webhooks or e-signature configuration. Another colleague is invited as **viewer**: they can open templates and submissions and download signed documents, but change nothing.

**Why this priority**: today every user of the instance is an administrator, so nobody outside the two admins can be given access; the role select already lists editor and viewer (disabled) and every screen already checks `can?`.

**Independent Test**: on staging, invite an editor and a viewer through `POST /api/ccn/users` with `role`; with an API token of each, the editor creates a template and a submission (200) but gets 403 on `/api/ccn/users` and `/api/ccn/account_configs`; the viewer lists templates and downloads a submission's documents (200) but gets 403 on `POST /api/templates/pdf` and `POST /api/submissions`.

**Acceptance Scenarios**:

1. **Given** `User::ROLES = admin, editor, viewer`, **When** an administrator invites or updates a user with `role: 'editor'` or `'viewer'` (UI form or `/api/ccn/users`), **Then** the role is saved and shown as a badge in Settings → Users; an unknown role is refused as today.
2. **Given** an editor, **When** they use the UI or the API (their own API token or MCP token), **Then** they can read, create, update, clone and archive templates and folders, create, read, update and archive submissions and submitters (send, resend, download), manage their own profile, signature, API token and MCP token; **Then** they cannot read or change account settings, personalization, notifications, e-signature, SMTP, storage, SSO, users, webhooks, or the account itself — the settings navigation shows only Profile, API and MCP entries, and every such request is refused (redirect with the CanCan message in the UI, 403 JSON in the API).
3. **Given** a viewer, **When** they use the UI or the API, **Then** they can read templates, folders, submissions and submitters and download documents, and manage their own profile and tokens; every create, update, destroy, send or resend is refused; the dashboard hides the "Create"/"Send" buttons as it already does for `cannot?`.
4. **Given** the account's only active administrator, **When** anyone tries to change their role to editor/viewer or to archive them, **Then** the request is refused with a documented 422 ("at least one administrator must remain"); demoting or archiving an admin is otherwise allowed.
5. **Given** an editor or viewer, **When** they open Settings → Users, **Then** they see the list read-only and the "Add user" button is disabled with "Contact your administrator to add new users" (the existing text); the Sidekiq console stays administrators-only (`User#sidekiq?` unchanged).
6. **Given** existing users (all `admin`) and the integration user, **When** the fork is deployed, **Then** nothing changes for them: no migration, `role` column unchanged, the default role for new users stays `admin` unless a role is given.

---

### User Story 4 - Bulk send from a CSV/XLSX list in the UI (Priority: P3, optional)

A staff member has a spreadsheet of 40 signers. On the "Send" page of a template, they pick the "List" tab, upload the file, map its columns to the template's roles and prefillable fields, review the count, and one click creates one submission per row, e-mails sent.

**Why this priority**: the API already does bulk (`POST /api/submissions` accepts many submissions); the UI slot (`submissions/_list_form`) exists; it is a convenience for staff who do not use Claude Code, and FORK-PLAN.md marks it optional.

**Independent Test**: upload a 3-row CSV with `email,name` (one role) on staging with `send_email` off: three submissions appear under the template, each with the row's e-mail and name.

**Acceptance Scenarios**:

1. **Given** a template with roles `Signer` (and optionally more), **When** a CSV or XLSX whose header row contains `email` (and optionally `name`, `phone`, one column per prefillable field, prefixed by the role name when several roles) is uploaded in the List tab, **Then** the page shows the detected columns, the row count and the first rows, and refuses a file without an `email` column or with more than 500 rows.
2. **Given** a valid file, **When** "Send" is confirmed, **Then** one submission per row is created through the same service as the API (`Submissions.create_from_submitters`), with `send_email` as chosen and prefilled values as read-only fields, and the user lands on the template's submissions list; a row with an invalid e-mail is reported by line number and the whole file is refused (nothing sent).

---

### Edge Cases

- Reminders: a signer with several due stages at once (long outage) receives one reminder per run, never a burst; durations need not be increasing — a later stage with a shorter duration simply becomes due at once after the previous one (documented, not validated, as the UI form does not validate either).
- Reminders: an account that cannot send e-mail (`Accounts.can_send_emails?` false — staging has no SMTP) → the run records nothing and reports the signers as skipped "no e-mail delivery configured"; no event is written for an e-mail that was not sent.
- Reminders: the invitation job sets `sent_at` once (`||=`); a resend does not restart the reminder clock (documented). Submitters created before `sent_at` existed (nil) are never reminded.
- Reminders: two scheduler processes (e.g. during a deploy overlap) → a run lock (Redis) makes the second run a no-op; a crash mid-run → the next run resumes from the events, no double send (the event is written in the same transaction step as the delivery, delivery first).
- Logo: SVG is refused (scripted content in e-mails and signing pages); files are checked by content type and magic bytes, not by extension; a logo of 5000×5000 px is accepted but displayed constrained by CSS; the blob is public-read by name (`logo`) so e-mail clients can fetch it without a session.
- Logo in e-mails when `APP_URL` is unset: the image URL cannot be absolute → the e-mail falls back to no logo (never a broken image); the settings page warns when `APP_URL` is blank.
- Roles: an editor who owns the API token used by Claude Code → the fork's `/api/ccn/...` administration endpoints answer 403 for them; the ingestion endpoints (templates, submissions) keep working. A viewer's token can list and download only.
- Roles: `User#sidekiq?` unchanged (admins only); impersonation (`true_user`) unchanged; the integration user (`role: 'integration'`) is untouched and still filtered out of lists.
- Roles: the last-admin guard counts active, non-integration administrators of the account; archiving through `DELETE /api/ccn/users/{id}` and the UI's remove button both apply it.
- Bulk (optional): XLSX with formulas → cell values as computed by the file (rubyXL reads cached values); dates → strings as displayed; more than one sheet → the first sheet only.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST send reminder e-mails to pending signers according to the account's `submitter_reminders` durations (`AccountConfigs::REMINDER_DURATIONS` keys mapped to `ActiveSupport::Duration`), stage k (1..3) being due when `now >= submitter.sent_at + duration_k` and fewer than k `send_reminder_email` events exist for the signer, and not due any more when `now > sent_at + duration_k + 7 days`; one stage at most per signer per run; at most `CCN_REMINDERS_MAX_PER_RUN` (default 50) e-mails per run, oldest due first.
- **FR-002**: A reminder MUST NOT be sent when the signer is completed or declined, the submission archived or expired, the template archived, the signer's e-mail blank, the signer's `preferences['send_email']` is `false`, the e-mail bounced in the last 24 hours (`Submitters.email_bounced_recently?`), or the account cannot send e-mail; `Submitters::ValidateSending` MUST run as for the invitation.
- **FR-003**: The reminder e-mail MUST be a new `SubmitterMailer` method rendering the account's `submitter_invitation_reminder_email` template (default `AccountConfig::DEFAULT_VALUES`) or the template's `invitation_reminder_email_subject`/`_body` preferences when present, with `ReplaceEmailVariables` and the same reply-to, from-address and sign-link (`SIGN_TTL`) rules as the invitation; each delivery MUST record `SubmissionEvent(event_type: 'send_reminder_email')` for the signer.
- **FR-004**: The scheduler MUST run only when `CCN_REMINDERS_ENABLED=true` (default off; on for staging), MUST tick at most every 15 minutes, MUST hold a run lock so concurrent processes do not double-send, and MUST be observable: `GET /api/ccn/reminders/due` (list of due signers with stage) and `POST /api/ccn/reminders/run` (execute one run now; `dry_run: true` counts only), administrators only, documented in `docs/openapi-ccn.json`.
- **FR-005**: The Settings → Notifications page MUST show, in the existing `_reminder_banner` hook, the reminder e-mail template form (subject, body, variables) saving `submitter_invitation_reminder_email` through `PersonalizationSettingsController`; the template preferences page MUST show the per-template override collapse in the existing empty `_submitter_invitation_reminder_email_collapse` hook; the "not available yet" placeholder MUST disappear for reminders.
- **FR-006**: `Account` MUST get `has_one_attached :logo` (no migration: ActiveStorage tables exist); uploads MUST be PNG, JPEG or WebP ≤ 2 MB validated by content type and magic bytes; the `_logo_form` hook MUST offer upload, preview and removal; `GET/PUT/DELETE /api/ccn/account_logo` MUST expose the same with the ingestion endpoints' `file` shapes (base64, data URI, https URL), documented in `docs/openapi-ccn.json`.
- **FR-007**: When a logo is attached, the signing page (`submit_form/*`), the start form (`start_form/*`) and the submitter e-mails MUST display it in place of the DocuSeal mark in their header, and the DocuSeal attribution in the page footer (`shared/attribution`) and e-mail footer (`shared/email_attribution`) MUST remain byte-identical; without a logo every page and e-mail MUST render exactly as before.
- **FR-008**: `User::ROLES` MUST become `admin editor viewer` (`ADMIN_ROLE` unchanged as default); `lib/ability.rb` MUST branch on `user.role`: admin = the current rules; editor = read/create/update/destroy on Template, TemplateFolder, Submission, Submitter (account-scoped) plus manage of their own UserConfig, EncryptedUserConfig, AccessToken, McpToken and `:mcp`, and read of User (list); viewer = read on Template, TemplateFolder, Submission, Submitter, User plus manage of their own UserConfig, EncryptedUserConfig, AccessToken, McpToken and `:mcp`; nothing else. `/api/ccn/...` administration MUST therefore answer 403 for editors and viewers through the existing `authorize!` calls, without controller changes.
- **FR-009**: The `_role_select` hook MUST enable the editor and viewer options; the users list MUST show the role badge (existing); demoting or archiving the last active administrator MUST be refused (UI and `/api/ccn/users`, MCP `manage_users`) with a translated 422; `UsersController#role_valid?` and `Ccn::ManageUsers` MUST accept the new roles unchanged (they read `User::ROLES`).
- **FR-010** (optional, US4): the `submissions/_list_form` hook MUST offer a CSV/XLSX upload (≤ 500 rows, header with `email`, optional `name`, `phone`, prefillable field columns, role-prefixed when several roles), a preview and a confirmation that creates one submission per row through `Submissions.create_from_submitters`; invalid rows MUST be reported by line and refuse the whole file.
- **FR-011**: Every touched upstream file MUST be listed in `CCN-CHANGES.md` with its reason; expected minimal edits: `app/models/user.rb` (ROLES), `lib/ability.rb` (role branches), `app/models/account.rb` (one `has_one_attached`), the two `_docuseal_logo` partials and `layouts/mailer.html.erb` (one render each), `config/routes.rb` (`/api/ccn/reminders`, `/api/ccn/account_logo`), `config/sidekiq.yml` only if a queue is added; a scheduling gem, if chosen, MUST be pinned and registered; no signing-path file; no migration.
- **FR-012**: Every behaviour above MUST have request specs (mailer, job, abilities per role, API 403 matrix, logo upload and rendering with attribution assertion, last-admin guard); the S4 gate script MUST exercise reminders (dry run + run + event), the logo (upload, signing page header, footer attribution, removal) and the roles matrix on staging with temporary users, leaving the account as it found it; `CLAUDE.md` (operations) and `docs/openapi-ccn.json` MUST document the new operations.

### Key Entities

- **Reminder stage**: derived, not stored — `(submitter, k)` with `k` = number of `send_reminder_email` events + 1, due time `sent_at + duration_k`, late limit `+ 7 days`.
- **SubmissionEvent `send_reminder_email`**: existing enum value; one row per reminder sent, `submitter_id`, `created_at` (the audit trail of reminders).
- **Account logo**: ActiveStorage attachment named `logo` on `Account` (public-read by name in the blob proxy), content type PNG/JPEG/WebP, ≤ 2 MB.
- **User role**: `admin` (everything), `editor` (documents and sending), `viewer` (read-only); `integration` unchanged and hidden.
- **Bulk list** (optional): a parsed spreadsheet — header columns mapped to role attributes and prefillable fields, rows → submissions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the specs, a signer sent 25 h ago with durations 24 h / 3 d / 7 d receives exactly one reminder on the first run, none on an immediate second run, the second reminder after 3 d and the third after 7 d, and never a fourth; every skip rule of FR-002 has an example.
- **SC-002**: On staging (S4 gate), with reminders enabled and set to 1 h / 2 h / 4 h: a signer whose `sent_at` is moved back 2 h is listed by `GET /api/ccn/reminders/due` for stage 1; `POST /api/ccn/reminders/run` reports it as skipped ("no e-mail delivery") because staging has no SMTP, and writes no event; with the spec's test delivery method the same run sends one e-mail and writes one event. The real e-mail is verified after promotion to production (or on staging if Luciano configures SMTP to his mailbox — §9 question 5).
- **SC-003**: On staging, a logo uploaded through the API is visible in the HTML of `/s/:slug` (an `<img>` pointing at the logo blob) and the footer still contains "DocuSeal" and the source-code link; after `DELETE /api/ccn/account_logo` the DocuSeal mark is back.
- **SC-004**: The roles matrix spec covers, for admin/editor/viewer, at least: templates create/read/update/archive, submissions create/read/archive, submitters send/resend/download, users list/invite, account configs read/write, webhooks read/write, folders create — with the expected 200/403 for each; on staging the same matrix is run with two temporary users and their API tokens, then the users are archived.
- **SC-005**: No 500 for any client-controlled input in the new endpoints, forms or uploads; every refusal is a translated message (en/fr).
- **SC-006**: Every upstream file touched in this stage is listed in `CCN-CHANGES.md`; no file under `lib/submitters/`, `lib/submissions/generate_*`, `lib/pdf_utils.rb`, `lib/pdfium.rb` is in the diff; no migration.

## Assumptions

- Reminder durations count from the initial send (`sent_at`), as DocuSeal's own settings wording ("first reminder in …") suggests; they are not relative to the previous reminder.
- Staging never e-mails (no SMTP): reminders are verified there by dry run and by the run's report; the delivered e-mail is verified in the specs and, for real, after promotion.
- `CCN_REMINDERS_ENABLED` is set to `true` on staging by `staging-compose.yml` and left unset on production until Luciano decides (FORK-PLAN.md §7 Stage 4a).
- The P1 set is the one Luciano named on 2026-09-14 (reminders, logo, roles); bulk CSV stays optional and is implemented last, only if the three P1 stories are green.
- Per-user template permissions (`TemplateAccess`, the Pro "template access" list) are out of scope; roles are account-wide.
