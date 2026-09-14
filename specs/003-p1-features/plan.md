# Implementation Plan: P1 features — reminders, account logo, editor/viewer roles

**Branch**: `ccn` | **Date**: 2026-09-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-p1-features/spec.md`

## Summary

Stage 4 of FORK-PLAN.md ships the three P1 stories Luciano named — automated signer reminders, an account
logo on the signing page/e-mails, and editor/viewer account roles — plus an optional P3 bulk CSV/XLSX send,
implemented last and only if the P1 stories are green. Every story reuses UI-only scaffolding that already
exists in the 3.2.4 tree (settings forms, hook partials, enum values, role-select options) and adds the piece
that is actually missing: the reminder scheduler + mailer, the logo attachment + rendering, the ability role
branches, and — optional — the list-upload controller. Design is fixed by `research.md` D1–D12 (verified
against the tree on 2026-09-14); this plan turns those decisions into files, phases and gates.

## Technical Context

**Language/Version**: Ruby 4.0.5 / Rails 8.1 (upstream 3.2.4); no front-end framework change (ERB partials,
existing Stimulus controllers reused where the hooks already wire them)

**Primary Dependencies**: `sidekiq-cron` 2.4.0 (new, pinned — D1); upstream models and service modules only
otherwise (`AccountConfig`, `AccountConfigs`, `SubmitterMailer`, `Submitters::ValidateSending`, `Accounts`,
`User`, `Ability`, `ActiveStorage`, `Marcel`); `csv` (stdlib) and `rubyXL` (already in the bundle) for the
optional bulk story

**Storage**: PostgreSQL, unchanged schema; `Account#logo` is an `ActiveStorage::Attachment` (join table
already exists, no migration); reminders read `AccountConfig`/`SubmissionEvent` rows, nothing new stored

**Testing**: RSpec request/mailer/job specs (`spec/requests/ccn_reminders_spec.rb`, `ccn_account_logo_spec.rb`,
`ccn_roles_spec.rb`, `spec/mailers/ccn_submitter_reminder_mailer_spec.rb`, `spec/jobs/ccn_send_submitter_reminders_job_spec.rb`,
`spec/lib/ccn/reminders_spec.rb`), ability specs per role (`spec/lib/ability_spec.rb` additions), e-mail
through the test delivery method

**Target Platform**: Linux/amd64 container on Coolify (staging first); `sidekiq-cron` needs no extra
infrastructure (Redis is already the Sidekiq backend)

**Project Type**: Rails monolith (web service + API), one new background job queue reused (`recurrent`,
already declared, currently unused)

**Performance Goals**: reminder sweep is one indexed-enough query per account per 15-minute tick, capped at
`CCN_REMINDERS_MAX_PER_RUN` (default 50) deliveries; logo upload/serve reuses the existing blob proxy; role
checks are in-memory CanCan rules, no extra queries per request

**Constraints**: no file under `lib/submitters/*`, `lib/submissions/generate_*`, `lib/pdfium.rb`,
`lib/pdf_utils.rb` is touched; no migration; upstream files edited (research D1, D5, D8–D10): `Gemfile` +
`Gemfile.lock` (sidekiq-cron), `app/models/user.rb` (`ROLES`, `include Ccn::LastAdminGuard`),
`app/models/account.rb` (`include Ccn::AccountLogo`), `lib/ability.rb` (role branches), `config/routes.rb`
(`/api/ccn/reminders/*`, `/api/ccn/account_logo`), `app/controllers/users_controller.rb` (rescue hook, D10),
`app/views/notifications_settings/_reminder_banner.html.erb`,
`app/views/templates_preferences/_submitter_invitation_reminder_email_collapse.html.erb`,
`app/views/personalization_settings/_logo_form.html.erb`, `app/views/submit_form/_docuseal_logo.html.erb`,
`app/views/start_form/_docuseal_logo.html.erb`, `app/views/layouts/mailer.html.erb`, `app/views/users/_role_select.html.erb`
— every one a hook fill-in or a one-line include/render, registered in `CCN-CHANGES.md`; `CCN_REMINDERS_ENABLED`
default off, on for staging only (`staging-compose.yml`); `sidekiq-cron`'s web UI panel is not mounted (no new
attack surface on `/sidekiq`)

**Scale/Scope**: single-tenant instance, a dozen users; 3 mandatory stories + 1 optional; ~6 new lib modules,
2 new controllers (REST) + 1 UI controller, 1 mailer, 1 job, 1 concern-per-model (logo, last-admin), ability
rewrite, ~10 upstream one-line hooks, ~1800 lines of new Ruby including specs

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Signing path untouched | ✅ no file under `lib/submitters`, `lib/submissions/generate_*`, `lib/pdfium.rb`, `lib/pdf_utils.rb` is edited; the reminder mailer and the logo render around the existing signing views, never inside PDF/result generation |
| II. Upstream is the contract | ✅ `docs/openapi.json` untouched, its contract spec stays green; new fork operations (`/api/ccn/reminders/*`, `/api/ccn/account_logo`) documented in `docs/openapi-ccn.json` with their own contract entries |
| III. Rebase-cheap | ✅ new files (`lib/ccn/*`, `app/mailers/ccn_*`, `app/jobs/ccn_*`, `app/controllers/api/ccn_*`); ~10 upstream edits, every one a single line or an empty-hook fill-in, registered in `CCN-CHANGES.md`; no migration; one new gem, pinned, registered |
| IV. Verified independently | ✅ request/mailer/job/ability spec per story; CI green per phase; diff-only review after phases 1–4 (reminders) and after phases 5–7 (logo, roles, docs); S4 gate script on staging before tagging |
| V. Licence / attribution | ✅ the DocuSeal attribution partials (`shared/_attribution`, `shared/_email_attribution`) are read, never edited; the logo replaces only the brand mark in the page/e-mail header, not the footer; source stays public |

## Project Structure

### Documentation (this feature)

```text
specs/003-p1-features/
├── plan.md              # this file
├── research.md          # D1–D12 + verified upstream facts
├── data-model.md         # due-rule, mailer, API shapes, ability matrix, bulk format
├── quickstart.md         # curl + admin walk-through = the S4 gate script's steps
├── contracts/README.md   # operation table → docs/openapi-ccn.json additions
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
app/controllers/api/
├── ccn_reminders_controller.rb          # GET /api/ccn/reminders/due, POST /api/ccn/reminders/run
└── ccn_account_logo_controller.rb       # GET/PUT/DELETE /api/ccn/account_logo
app/controllers/
├── ccn_account_logos_controller.rb      # UI: create/destroy (Settings → Personalization)
└── users_controller.rb                  # UPSTREAM: rescue_from ActiveRecord::RecordInvalid (D10, one line)
app/mailers/
└── ccn_submitter_reminder_mailer.rb     # < SubmitterMailer, reminder_email(submitter)
app/views/ccn_submitter_reminder_mailer/
└── reminder_email.html.erb
app/jobs/
└── ccn_send_submitter_reminders_job.rb  # Sidekiq job, sidekiq-cron entry point
lib/ccn/
├── reminders.rb                         # DURATIONS, due(account, now:), run(account:, now:, dry_run:)
├── account_logo.rb                      # concern: has_one_attached :logo + validation
├── last_admin_guard.rb                  # concern: User validation, ccn_last_admin_required
├── users_controller_guard.rb            # concern: rescue_from → redirect_back alert (UI)
└── submissions_lists.rb                 # optional (US4): parse CSV/XLSX → rows → submissions
app/controllers/
└── ccn_submissions_lists_controller.rb  # optional (US4): Send page "List" tab
app/models/
├── user.rb                              # UPSTREAM: ROLES + include LastAdminGuard (2 lines)
└── account.rb                           # UPSTREAM: include Ccn::AccountLogo (1 line)
lib/ability.rb                           # UPSTREAM: role branches (D9)
app/views/
├── notifications_settings/_reminder_banner.html.erb              # UPSTREAM hook: fill in
├── templates_preferences/_submitter_invitation_reminder_email_collapse.html.erb  # UPSTREAM hook: fill in
├── personalization_settings/_logo_form.html.erb                  # UPSTREAM hook: fill in
├── submit_form/_docuseal_logo.html.erb                           # UPSTREAM: render shared/_ccn_brand_logo
├── start_form/_docuseal_logo.html.erb                            # UPSTREAM: render shared/_ccn_brand_logo
├── shared/_ccn_brand_logo.html.erb                                # new partial
├── shared/_ccn_mailer_logo.html.erb                               # new partial
├── layouts/mailer.html.erb                                        # UPSTREAM: one render line
├── users/_role_select.html.erb                                    # UPSTREAM: enable editor/viewer options
└── submissions/_list_form.html.erb                                # optional (US4) UPSTREAM hook: fill in
config/
├── routes.rb                            # UPSTREAM: reminders + account_logo + lists routes
├── initializers/zz_ccn_reminders.rb     # sidekiq-cron schedule, gated on CCN_REMINDERS_ENABLED
└── locales/ccn/ccn.yml                  # + ccn_last_admin_required and reminder/logo/list messages
Gemfile, Gemfile.lock                    # UPSTREAM: + sidekiq-cron 2.4.0
docs/openapi-ccn.json                    # + reminders, account_logo operations
spec/requests/ccn_reminders_spec.rb, ccn_account_logo_spec.rb, ccn_roles_spec.rb, ccn_submissions_lists_spec.rb
spec/mailers/ccn_submitter_reminder_mailer_spec.rb
spec/jobs/ccn_send_submitter_reminders_job_spec.rb
spec/lib/ccn/reminders_spec.rb, account_logo_spec.rb, last_admin_guard_spec.rb, submissions_lists_spec.rb
spec/lib/ability_spec.rb                 # UPSTREAM (or new file): editor/viewer matrix
```

**Structure Decision**: same conventions as Stage 2/3 — new behaviour lives in `lib/ccn/*` modules called from
thin controllers/mailers/jobs; every upstream file gets the smallest possible edit (one include, one render,
one rescue, one case branch) so a future rebase touches the same handful of lines; the reminder scheduler is a
Sidekiq job + `sidekiq-cron` entry rather than a web-request-driven poll, matching how the app already runs
recurring work.

## Design decisions (summary; rationale in research.md)

1. **Reminders — scheduler**: `sidekiq-cron` 2.4.0 pinned, loaded only when `CCN_REMINDERS_ENABLED=true` and
   `Sidekiq.server?`; ticks every 15 minutes; `CcnSendSubmitterRemindersJob` on the existing `recurrent` queue.
2. **Reminders — due rule**: stage `k` = prior `send_reminder_email` events + 1 (≤ 3); due at `sent_at +
   duration_k`; expired (never sent) after `+7 days`; one stage per signer per run; `CCN_REMINDERS_MAX_PER_RUN`
   (default 50) deliveries per run, oldest `sent_at` first.
3. **Reminders — run safety**: a Redis lock (`nx`, TTL 14 min) serializes concurrent processes; the audit event
   is written immediately after delivery, so a crash can at worst repeat one send once, never burst.
4. **Reminders — mailer**: `CcnSubmitterReminderMailer < SubmitterMailer` mirrors `invitation_email` exactly
   (subject/body resolution order: template preference → account config → default; reply-to, from-address,
   sign-link, `ValidateSending`), so behaviour a reader already knows from the invitation applies unchanged.
5. **Reminders — observability**: `Ccn::Reminders.due`/`.run` behind `GET /api/ccn/reminders/due` and
   `POST /api/ccn/reminders/run` (`dry_run`), admins only; no MCP tool (running reminders from a model
   transcript is not wanted — only the durations, via the existing `account_config` tool).
6. **Reminders — UI**: the two empty hooks (`_reminder_banner`, the per-template collapse) get the same form
   shape as the existing invitation-email settings, bound to the keys that already exist.
7. **Logo — attachment**: `has_one_attached :logo` via a one-line-include concern on `Account`; PNG/JPEG/WebP
   ≤ 2 MB, checked by declared type and magic bytes (SVG refused — script risk in e-mails/signing pages); the
   blob is served by the existing "named `logo` is public" rule in both blob proxies (no new auth code).
8. **Logo — rendering**: one new partial (`shared/_ccn_brand_logo`) used by the two `_docuseal_logo` hooks and
   by the mailer layout; the attribution partials are never touched, so §7(b) compliance is structural, not a
   thing to remember to preserve; app pages (dashboard, settings) keep the DocuSeal mark — the logo is for
   signers and e-mail recipients only.
9. **Roles — ability**: `User::ROLES` gains `editor`/`viewer`; `lib/ability.rb` branches on `user.role` (admin
   unchanged, editor = manage on documents/sending, viewer = read-only), so every existing `authorize!`/`can?`
   check in the app and the `/api/ccn/...` controllers enforces the new roles with zero controller changes.
10. **Roles — last-admin guard**: a `User` validation (one concern, one include) refuses a save that would
    leave the account without an active, non-integration admin; surfaces as the same 422/`RecordInvalid` path
    every other guard in this fork uses.
11. **Bulk (optional, US4)**: `Ccn::SubmissionsLists` parses CSV (stdlib) or XLSX (`rubyXL`, already bundled),
    ≤ 500 rows, reuses `Submissions.create_from_submitters` (the same path the API's bulk `POST /api/submissions`
    uses) so behaviour matches the documented API exactly; implemented only after US1–US3 are green.
12. **Environment/gate**: `CCN_REMINDERS_ENABLED=true`, `CCN_REMINDERS_MAX_PER_RUN=50` in `staging-compose.yml`
    only; `staging-s4-check.sh` exercises reminders (due/run/event, dry vs. real), logo (upload, page HTML,
    attribution still present, delete), and the roles matrix (two temporary users, archived after); tag
    `3.2.4-ccn.5` once CI, review and gate all pass.

## Phases

| Phase | Content | Verification |
|-------|---------|---------------|
| 1 Setup | `sidekiq-cron` in `Gemfile`/`Gemfile.lock`, `zz_ccn_reminders.rb` initializer, `Ccn::Reminders::DURATIONS` + due-rule spec, locale keys | CI green |
| 2 Reminders mailer + job (US1) | `CcnSubmitterReminderMailer` + view, `Ccn::Reminders.due/.run`, `CcnSendSubmitterRemindersJob`, Redis lock | mailer/job/lib specs: due rule (SC-001 cases), skip rules (FR-002), idempotency, lock, `can_send_emails?` false → skipped not sent |
| 3 Reminders API + UI (US1) | `Api::CcnRemindersController`, routes, `_reminder_banner` + per-template collapse filled in | request spec: `due`/`run` shapes, `dry_run`, admin-only; UI renders the form and saves through the existing settings controller |
| — Review A | diff-only reviewer on phases 1–3 | findings fixed, CI green |
| 4 Account logo (US2) | `Ccn::AccountLogo` concern, `CcnAccountLogosController` (UI), `Api::CcnAccountLogoController`, `shared/_ccn_brand_logo` + `_ccn_mailer_logo` partials, the four hook/layout edits | request spec: upload validation (type/size/magic bytes), signing-page + e-mail rendering with attribution assertion (FR-007), removal restores the mark |
| 5 Roles (US3) | `User::ROLES`, `Ccn::LastAdminGuard`, `lib/ability.rb` branches, `_role_select` enabled, `Ccn::UsersControllerGuard` | ability spec matrix (admin/editor/viewer × the SC-004 operation list), request spec: `/api/ccn/...` 403 for editor/viewer per FR-008, last-admin guard 422 (UI + API + MCP) |
| — Review B | diff-only reviewer on phases 4–5 | findings fixed, CI green |
| 6 Docs | `docs/openapi-ccn.json` (+reminders, +account_logo), contract spec extended, `CCN-CHANGES.md`, quickstart | contract spec green |
| 7 Bulk list (US4, optional) | `Ccn::SubmissionsLists`, `CcnSubmissionsListsController`, `_list_form` hook filled in | request/lib spec: CSV + XLSX parse, ≤500 rows, invalid-row refusal, one submission per row via `create_from_submitters` |
| — Review C | diff-only reviewer on phases 6–7 (or 6 alone if US4 deferred) | findings fixed, CI green |
| 8 Gate + release | `staging-s4-check.sh`, tag `3.2.4-ccn.5`, deploy, S1 + bounds + S2 + S3 + S4 gates, `CLAUDE.md`, `LOOP-STATE.md`, memory | all gates PASS |

## Complexity Tracking

| Item | Why it is needed | Simpler alternative rejected |
|------|-------------------|-------------------------------|
| New gem (`sidekiq-cron`) | recurring reminder sweep needs a scheduler; the app has no cron mechanism today | a self-re-enqueueing job (research D1: dies on a crash between run and re-enqueue, needs a boot-time repair) or a Coolify scheduled task (infra-only, invisible in the repo, breaks constitution III) |
| ~10 one-line upstream edits across models/views/routes | each hook, include or render point is the only place the behaviour can attach without duplicating upstream logic | forking whole upstream files to avoid any edit — multiplies the rebase surface far more than ten one-liners |
| Ability rewritten with role branches (not per-action overrides) | the existing `Ability` class has no role concept at all; a role-blind app cannot express "editor vs. viewer" any other way | per-controller role checks (would duplicate CanCan's own authorization and could drift from the UI's `can?` calls) |
