---
description: "Task list for Stage 4 — P1 features (reminders, account logo, editor/viewer roles) + optional bulk list"
---

# Tasks: P1 features — reminders, account logo, editor/viewer roles

**Input**: Design documents from `specs/003-p1-features/` (plan.md, spec.md, research.md, data-model.md, contracts/README.md)

**Tests**: a request/mailer/job/lib spec per task is part of every task (constitution IV). CI must stay green
after every phase; a diff-only reviewer reads phases 1–3 before phase 4 starts, phases 4–5 before phase 6,
and phases 6–7 before the gate.

**Organization**: phase 1 is plumbing; phases 2–3 map to US1 (reminders); phase 4 is US2 (logo); phase 5 is
US3 (roles); phase 6 is US6-equivalent (docs); phase 7 is US4 (bulk list, optional — P3); phase 8 is the gate
and release.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [x] T001 `Gemfile`: `gem 'sidekiq-cron', '2.4.0'`; `bundle lock`; register in `CCN-CHANGES.md` (research D1)
- [x] T002 `lib/ccn/reminders.rb` — `DURATIONS` (16 keys, `AccountConfigs::REMINDER_DURATIONS.keys` mirrored to `ActiveSupport::Duration`) + `spec/lib/ccn/reminders_spec.rb` asserting `DURATIONS.keys == AccountConfigs::REMINDER_DURATIONS.keys`
- [x] T003 `config/initializers/zz_ccn_reminders.rb` — registers `CcnSendSubmitterRemindersJob` on `Sidekiq::Cron::Job` at `*/15 * * * *`, only when `ENV['CCN_REMINDERS_ENABLED'] == 'true'` and `Sidekiq.server?`
- [x] T004 [P] Locale keys en/fr in `config/locales/ccn/ccn.yml`: `ccn_last_admin_required`, `ccn_logo_invalid_type`, `ccn_logo_too_large`

## Phase 2: Reminders mailer + job (US1)

- [x] T005 `Ccn::Reminders.due(account, now:)` and `.run(account:, now:, dry_run:)` in `lib/ccn/reminders.rb` per data-model.md's due rule (stage/skip/late-expiry logic, `CCN_REMINDERS_MAX_PER_RUN` cap, oldest-first) + spec cases: SC-001 sequence (25h → stage 1 only, idempotent immediate rerun, stage 2 after 3d, stage 3 after 7d, never a 4th), every FR-002 skip reason, backlog-late skip (>7d past due), per-run cap, Redis run lock (`nx`, `ex 840`) rejecting a concurrent run
- [x] T006 `app/mailers/ccn_submitter_reminder_mailer.rb` (`< SubmitterMailer`, `reminder_email(submitter)` — subject/body resolution order: template preference → account config → default; `ReplaceEmailVariables`, `build_submitter_reply_to`, `maybe_set_custom_domain`, `from_address_for_submitter`, `Submitters::ValidateSending.call`) + view `app/views/ccn_submitter_reminder_mailer/reminder_email.html.erb` + `spec/mailers/ccn_submitter_reminder_mailer_spec.rb` (each resolution tier, validation failure raises before send, reply-to/from/sign-link match the invitation mailer's rules)
- [x] T007 `app/jobs/ccn_send_submitter_reminders_job.rb` — iterates accounts with `submitter_reminders` configured, calls `Ccn::Reminders.run`, writes `SubmissionEvent(event_type: 'send_reminder_email')` immediately after each `deliver_now!` (delivery-then-event order, research D4) + `spec/jobs/ccn_send_submitter_reminders_job_spec.rb` (event written once per send, `Accounts.can_send_emails?` false → skipped not sent/no event, crash-after-delivery-before-event scenario documented as an accepted rare double-send, never a burst)

## Phase 3: Reminders API + UI (US1)

- [x] T008 Routes: `get 'reminders/due'`, `post 'reminders/run'` inside the existing `scope 'ccn'` block in `config/routes.rb`; register in `CCN-CHANGES.md`
- [x] T009 `app/controllers/api/ccn_reminders_controller.rb` (`due`/`run`, `dry_run` param, `include Ccn::AdminErrors`, `authorize!(:manage, current_account)`) + `spec/requests/ccn_reminders_spec.rb` (due shape with stage, run shape with sent/skipped/locked/disabled, dry_run computes without sending, non-admin token 403 — placeholder assertion until phase 5 lands the role branches, then re-verified in T018)
- [x] T010 [P] UI hooks: `app/views/notifications_settings/_reminder_banner.html.erb` (form for `submitter_invitation_reminder_email`, posts to the existing `settings_personalization_path`, mirrors `_signature_request_email_form`) and `app/views/templates_preferences/_submitter_invitation_reminder_email_collapse.html.erb` (per-template override, fields `invitation_reminder_email_subject/body`, mirrors the invitation collapse) filled in; request spec assertion added to `ccn_template_admin_spec.rb` (Stage 3) confirming the preference keys still round-trip through `PUT /api/templates/{id}`

## Review A (after phase 3)

- [x] T011 Diff-only reviewer on phases 1–3 (delta from `afce2904`); findings fixed; CI green

## Phase 4: Account logo (US2)

- [x] T012 `lib/ccn/account_logo.rb` (concern: `has_one_attached :logo`, `validate :ccn_logo_format` — declared content type ∈ PNG/JPEG/WebP **and** `Marcel::MimeType.for(io)` match, ≤ 2 MB, SVG refused) + one-line `include Ccn::AccountLogo` in `app/models/account.rb` + `spec/lib/ccn/account_logo_spec.rb` (each accepted type, oversize refused, magic-byte mismatch refused, SVG refused)
- [x] T013 `app/controllers/ccn_account_logos_controller.rb` (UI `create`/`destroy`, multipart, `authorize!(:manage, current_account)`) + `app/views/personalization_settings/_logo_form.html.erb` filled in (upload, preview, remove)
- [x] T014 Routes `get/put/delete 'account_logo'` in the `scope 'ccn'` block; `app/controllers/api/ccn_account_logo_controller.rb` (`show`/`update`/`destroy`, `file` via `Ccn::DocumentParams` base64/data-URI/https-URL shapes) + `spec/requests/ccn_account_logo_spec.rb` (upload each shape, 404 with no logo, validation 422s, delete)
- [x] T015 `app/views/shared/_ccn_brand_logo.html.erb` (`account.logo.attached? ? image_tag(...) : render('shared/logo')`) + `app/views/shared/_ccn_mailer_logo.html.erb` (absolute-URL variant, blank when `APP_URL` unset) + edits: `app/views/submit_form/_docuseal_logo.html.erb`, `app/views/start_form/_docuseal_logo.html.erb` (render the new partial), `app/views/layouts/mailer.html.erb` (one render line before `yield`) + spec assertions (extend `ccn_account_logo_spec.rb`): `/s/:slug` HTML contains the logo `<img>` when attached and the DocuSeal mark when not, `shared/_attribution` text byte-identical either way (FR-007), a signature-request e-mail (test delivery) includes the logo image tag and keeps "Sent using DocuSeal"

## Phase 5: Roles (US3)

- [x] T016 `app/models/user.rb`: `ROLES = %w[admin editor viewer].freeze` (line), `include Ccn::LastAdminGuard` (line); `lib/ccn/last_admin_guard.rb` (validation refusing a save that would leave the account without an active non-integration admin, message `ccn_last_admin_required`) + `spec/lib/ccn/last_admin_guard_spec.rb` (role change away from admin refused when last, archive refused when last, allowed when another admin remains, allowed for non-admin-affecting changes)
- [x] T017 `lib/ability.rb`: role branches per research D9 (admin unchanged; editor = create/read/update/destroy Template/TemplateFolder, manage Submission/Submitter, read User, manage own tokens; viewer = read Template/TemplateFolder/Submission/Submitter/User, manage own tokens) + `spec/lib/ability_spec.rb` matrix (admin/editor/viewer × Template/TemplateFolder/Submission/Submitter/User/Account/AccountConfig/WebhookUrl, each expected verb)
- [x] T018 `app/views/users/_role_select.html.erb` (enable editor/viewer options); `lib/ccn/users_controller_guard.rb` (concern: `rescue_from ActiveRecord::RecordInvalid` → `redirect_back(fallback_location: ..., alert: ...)`) + one-line `include Ccn::UsersControllerGuard` in `app/controllers/users_controller.rb`; `spec/requests/ccn_roles_spec.rb` — SC-004 matrix: editor and viewer API tokens against `/api/ccn/users|webhooks|account_configs` (403), `/api/ccn/template_folders` (editor 200/viewer read-only), `/api/templates/pdf`+`/api/submissions` (editor 200, viewer 403), `GET /api/templates`+`GET /api/submissions/{id}/documents` (both 200); last-admin guard 422 via `PUT /api/ccn/users/{self}` and MCP `manage_users`; re-verify T009's reminders 403 for non-admin now that roles exist

## Review B (after phase 5)

- [ ] T019 Diff-only reviewer on phases 4–5; findings fixed; CI green

## Phase 6: Documentation

- [x] T020 `docs/openapi-ccn.json`: 5 new operations (`listDueReminders`, `runReminders`, `getAccountLogo`, `setAccountLogo`, `deleteAccountLogo`) per contracts/README.md, `x-ccn-role-note` on the operations whose 403 behaviour changed with roles
- [x] T021 `spec/requests/ccn_openapi_contract_spec.rb` extended: the 5 new operations routable with a conforming 200
- [x] T022 [P] `CCN-CHANGES.md`: every file touched in phases 1–5 (Gemfile, initializers, models, `lib/ability.rb`, views, routes) with its reason; quickstart.md verified against the spec examples

## Phase 7: Bulk list (US4, optional — implement only if phases 1–6 are green and time remains)

- [ ] T023 `lib/ccn/submissions_lists.rb` — `parse(file, template)` (CSV via stdlib, XLSX via `RubyXL::Parser`, first sheet only, ≤ 500 rows, header requires `email`, role-prefixed columns for multi-role templates) returning `{columns, rows_count, preview, errors}` or per-line errors + `spec/lib/ccn/submissions_lists_spec.rb` (CSV happy path, XLSX happy path, missing `email` column refused, >500 rows refused, bad row reported by line, whole file refused on any error)
- [ ] T024 `app/controllers/ccn_submissions_lists_controller.rb` (`preview`/`create`, calls `Submissions.create_from_submitters` per row) + `app/views/submissions/_list_form.html.erb` filled in (upload, column mapping, preview, confirm) + `spec/requests/ccn_submissions_lists_spec.rb` (3-row CSV → 3 submissions with `send_email` as chosen, invalid file refused with nothing created)

## Review C (after phase 6, or phases 6–7 if US4 was implemented)

- [ ] T025 Diff-only reviewer on phases 6 (and 7 if implemented); findings fixed; CI green

## Phase 8: Gate + release

- [ ] T026 `staging-s4-check.sh`: reminders (set short durations by API, create a submission by API, move `sent_at` back via `rails runner` over `ssh coolify-vm` — never by editing signer-visible state any other way —, `GET …/due` lists stage 1, `POST …/run` with `dry_run:true` then real: staging has no SMTP so it reports the signer skipped "no e-mail delivery" and writes no event, config restored); logo (upload by API, `/s/:slug` HTML has the `<img>` and unchanged attribution text, `DELETE` restores the mark); roles (invite one editor + one viewer by API, mint their tokens via the runner into shell variables — never printed —, run the SC-004 200/403 matrix, archive both, confirm last-admin guard 422 on the gate's own admin) — no 5xx anywhere, account left as it found it
- [ ] T027 Tag `3.2.4-ccn.5`, image build, `staging-deploy-tag.sh 3.2.4-ccn.5`, gates S1 + bounds + S2 + S3 + S4 all PASS
- [ ] T028 `CLAUDE.md` (operations directory) cheat sheet: `/api/ccn/reminders/*`, `/api/ccn/account_logo`, the role matrix, `CCN_REMINDERS_ENABLED`; `LOOP-STATE.md`; memory (`docuseal-fork-plan.md`, `MEMORY.md`)

## Dependencies

- Phase 1 → everything. Phase 2 → phase 3 (API wraps the lib). Phase 3 needs phase 1's routes scope. Phase 4
  independent of phases 2–3 ([P] candidate at the phase level, but the plan runs it after Review A to keep one
  reviewer pass per logical group). Phase 5 independent of phase 4 in code but its request spec (T018)
  re-verifies phase 3's admin-only assumption (T009), so phase 5 must land before phase 6. Phase 6 needs
  phases 2–5. Phase 7 optional, after phase 6, before the final review/gate. Phase 8 needs the last review and
  (if skipped) an explicit note in `LOOP-STATE.md` that US4 was deferred.
