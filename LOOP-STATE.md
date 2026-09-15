# LOOP-STATE — Stage 4 (specs/003-p1-features)

Read this first on every run. Task list: `specs/003-p1-features/tasks.md` (28 tasks, 8 phases, 3 review
gates). Constitution: `.specify/memory/constitution.md`. Operations cheat sheet: `~/Projets_apps_github/DocuSeal/CLAUDE.md`.

**Scope of this stage**: US1 reminders, US2 account logo, US3 editor/viewer roles, US4 bulk CSV list
(optional, P3). Ended at tag `3.2.4-ccn.5` on **staging**; promotion to production was Luciano's separate
decision and he took it the same day — **`3.2.4-ccn.5` is live on production since 2026-09-15**, see
*Promotion* at the foot of this file.

## How the work is verified here

- RSpec cannot run on this Mac: the app needs libvips, PostgreSQL and Redis, none of them installed, and
  installing them was judged out of scope. **rubocop, erb_lint and brakeman do run locally** and are run
  before every push; **rspec is verified on CI** (`gh run list -R lucouto/docuseal-ccn`), ~5 min per round.
- Per constitution IV: max 3 fix attempts per failing item, then it is marked blocked below.

## Phase status

| Phase | Tasks | Status |
|-------|-------|--------|
| 1 Setup | T001–T004 | **done** (`55c4cfd3`, verified against the tree on 2026-09-15) |
| 2 Reminders mailer + job (US1) | T005–T007 | **done** (`55c4cfd3`) |
| 3 Reminders API + UI (US1) | T008–T010 | **done** (`55c4cfd3`) |
| Review A | T011 | **done** — 5 findings, all fixed in `822e77bb`; brief + outcome in `REVIEW-A-BRIEF.md` |
| 4 Account logo (US2) | T012–T015 | **done** — CI round 1 found 2 spec failures (multipart), fixed |
| 5 Roles (US3) | T016–T018 | **done** — CI round 1 found 1 spec failure (a lazy `let`), fixed |
| Review B | T019 | **done** — 1 HIGH + 6 LOW; 4 fixed, 3 recorded, 1 needs Luciano (see `REVIEW-B-BRIEF.md`) |
| 6 Documentation | T020–T022 | **done** — CI green (543 examples) on `85213247` |
| 7 Bulk list (US4, optional) | T023–T024 | **done** — implemented: phases 1–6 were green and budget remained |
| Review C | T025 | **done** — 2 HIGH + 6 MEDIUM + 6 LOW; all fixed but one, recorded (see `REVIEW-C-BRIEF.md`) |
| 8 Gate + release | T026–T028 | **done** — `3.2.4-ccn.5` live on staging, all five gates PASS (see below) |

## Stage 4 gate results — `3.2.4-ccn.5` on staging, 2026-09-15

| Gate | Result |
|------|--------|
| `staging-s1-check.sh` (formulas, conditions, attribution) | PASS |
| `staging-s1-bounds-check.sh` (formula DoS bounds) | PASS |
| `staging-s2-check.sh` (the 8 ingestion operations) | 27 passed, 0 failed |
| `staging-s3-check.sh` (the admin API + MCP) | 42 passed, 0 failed |
| `staging-s4-check.sh` (reminders, logo, roles, last-admin) | 43 passed, 0 failed, 0 skipped |

Two bugs in the **gate script itself** were found by running it, both of which would have made it lie:

- `docker exec` starts in the image's WorkingDir (`/data/docuseal`), where there is no Gemfile, so every
  `rails runner` step failed — and they were classed as *skips*, so the script would have printed
  "0 failed" and exited 0 having checked almost nothing. It now passes `-w /app`, and an unreachable runner
  is a **failure**, not a skip.
- The last-admin assertion counted administrators **globally**. Staging carries a testing account beside the
  real one, each with a single admin, so a global count said "two administrators" and the script took the
  wrong branch. The guard itself was right all along — it is account-scoped, and refused to demote the last
  admin of account 1. The count is now scoped the same way.

## What the next run must know

- **tasks.md checkboxes were stale** through phase 3 (work landed without ticking them). They are now
  reconciled: T001–T011 ticked against the code, not against the checkbox.
- **Phase 4 decisions** (beyond what plan/research already fixed):
  - The magic-byte check reads the attachable with **no filename hint** (`Marcel::MimeType.for(io)`), so an
    SVG renamed `.png` and declared `image/png` is refused — verified: Marcel reads it as `application/xml`.
  - `Ccn::AccountLogo.email_host_configured?` gates the logo in e-mails: with no `APP_URL` env and no
    `app_url` EncryptedConfig row, `Docuseal.default_url_options` falls back to localhost, so the e-mail
    keeps the DocuSeal mark rather than shipping a broken image. The settings page says so
    (`ccn_logo_missing_app_url`).
  - `Ccn::AccountLogo.account_for(@submitter, @submission, @template)` resolves the account in the
    signer-facing views, whose controllers set different ivars (a Submitter on `/s/:slug`, a Submission or a
    Template on the start form and its variants).
  - Per research D8 the logo replaces only the **mark**; the "DocuSeal" wordmark next to it and the footer
    attribution are untouched, which is what keeps §7(b) structural rather than a thing to remember.
  - `Ccn::DocumentParams.file_from` was added for a payload with one named `file` key (`decode` grew an
    optional `param:` for the message; every existing call site is unchanged).
- **Phase 4, CI round 1** — two spec failures, both mine, both about multipart: `ApiPathConsiderJsonMiddleware`
  rewrites the content type of *every* `/api` request to `application/json` (bar four whitelisted suffixes),
  so a `-F file=@logo.png` can never reach an API controller as a file. The API takes base64/data URI/https
  URL only; the multipart branch was removed as dead code and the settings page (which is not under `/api`)
  got the upload request spec instead. **Generalizable: no `/api/...` endpoint in this fork can take a
  multipart upload.**
- **Phase 5 decisions**:
  - **A CanCan class-level check ignores a rule's conditions** (`matches_non_block_conditions` returns
    `@base_behavior` when the subject is a Class). Giving every role `can :manage, User, id: user.id` — which
    ProfileController's `authorize!(:manage, current_user)` requires — therefore made `can?(:manage, User)`
    true for editors and viewers, and `Api::CcnUsersController`/`Mcp::CcnManageUsersController` gated exactly
    on that: **an editor could have listed and invited users, including administrators.** Both now gate on
    `authorize!(:manage, current_account)` (an instance, so conditions are evaluated), matching what
    `CcnRemindersController` and `CcnAccountLogoController` already did. Both files are fork-owned (Stage 3),
    so this is not an upstream edit — but it *is* a deviation from FR-008's "without controller changes", and
    it is the first thing Review B should look at. Every other admin endpoint was checked and is safe:
    webhooks and account configs have no rule at all for these roles, and `template_folders` is
    editor-by-design.
  - **`/api/ccn/template_folders` refuses a viewer even on GET**, because the namespace asks for `manage` in
    one before_action. contracts/README.md says "viewer 200 on GET"; FR-008 says the 403s must come from the
    existing authorize! calls. Resolved in favour of FR-008 — to be noted on the operation in T020 rather
    than worked around with a second authorize! call.
  - **The last-admin guard is only reachable from someone else's hands**: both the UI and `Ccn::ManageUsers`
    refuse a self role/archive change first, so the case the guard actually prevents is the *integration*
    account (automation) archiving or demoting the last human administrator. That is what the request spec
    exercises, alongside the one reachable UI path (`PUT /users/:id` with `archived_at` on oneself, which
    upstream does not strip) and `DELETE /users/:id`, which archives with `update!` and would be a 500
    without `Ccn::UsersControllerGuard`.
- **Review B's HIGH is the one to remember**: `f.select` built from a block never marks an option `selected`
  (`options_for_select` returns a String container untouched). Enabling the editor/viewer options turned a
  latent bug into a live privilege escalation — the Edit-user form always showed *Admin*, and the form
  permits `role`. Any other `f.select … do` in this fork deserves the same look.
- **Phase 7 decisions**:
  - The rows travel from the preview to the send in a **signed payload** (`ApplicationRecord.signed_id_verifier`,
    1 hour, its own purpose, template id inside), not a re-upload and not a session: what is confirmed is
    what was previewed, and it cannot be edited on the way. A payload signed for another template is refused.
  - A row's address is validated with the rule `Params::BaseValidator` applies on the API (typo correction
    included), so a row the list accepts is one `POST /api/submissions` would have accepted.
  - The preview is keyed by the **raw header**, not by the normalized column name: with two roles both
    columns are called `email` and one would otherwise overwrite the other.
  - A column naming nothing is dropped rather than refused, and the preview shows only the columns that were
    understood — a misspelt header is then visible as a missing column instead of silently ignored.
- **Review C's two HIGH findings are the ones to remember**, both in the bulk list and both about trusting a
  file: an `.xlsx` is a zip, so an upload cap says nothing about what a parser will build in memory (row XML
  deflates at better than 200:1 — a 0.1 MB file declaring 68 MB was measured here); and a feature that
  creates submissions must take `submitters_order` from the template, because `random` on a sequential
  template invites the counter-signatory before the first party has signed.
- **What Excel actually writes** (found by Review C, worth keeping): "CSV UTF-8" starts with a byte-order
  mark, a French Windows exports `;` rather than `,`, and plain "CSV" on Windows is cp1252. All three used to
  fail or mangle names here. `Ccn::SubmissionsLists.decode_text`/`delimiter_of` handle them.
- **Needs validation (Luciano)**:
  - **The S4 gate cannot be closed in full on staging.** `FORK-PLAN.md` §10 asks for "one real reminder in
    Luciano's mailbox from staging", and the constitution forbids exactly that ("staging never e-mails";
    `staging-compose.yml` deliberately declares no `SMTP_*`). `spec.md` anticipated the clash — SC-002 defers
    the real delivery to "after promotion to production, or on staging if Luciano configures SMTP to his own
    mailbox". Everything else in the S4 gate runs; the delivered e-mail is covered by the mailer spec only.
    Luciano's call: point staging SMTP at his own mailbox for one run, or accept the deferral to promotion.
  - US4's *visual* flow (the Upload list tab, the preview page) has request-spec coverage end to end but has
    never been opened in a browser — no way to run the app on this machine. Worth one manual pass on staging.
- **Settled by Luciano (2026-09-15)**:
  - **The start form is fine as it is.** He looked at `/d/:slug` with the CCN logo in place and approved
    keeping upstream's `<h1 class="text-5xl">DocuSeal</h1>` beside it — research D8 stands, the logo replaces
    the mark and not the wordmark. Do not "fix" this later.
  - **The CCN logo stays on staging.** `ccn-logo-fr-noir-1200.png` from the charte graphique skill (black
    version, because the signing page is off-white) is uploaded on the staging account. The S4 gate still
    passes with it: it snapshots an existing logo, uploads its own, and restores the original at the end.
  - Worth knowing when the same question comes up: the account logo never appears on the app's own pages —
    the dashboard at `/` keeps the DocuSeal mark by design (spec.md US2 scenario 5). It shows on `/s/:slug`,
    `/d/:slug` and in e-mails, and nowhere else.
- **Blocked**: nothing.

## Promotion — `3.2.4-ccn.5` on production, 2026-09-15

Luciano said "deploy to production" after reviewing the staging gate results. Procedure as recorded in
`~/Projets_apps_github/DocuSeal/CLAUDE.md`: `prod-preflight.sh` → `prod-deploy-compose.sh prod-compose.yml`
→ `prod-gates.sh`. Full entry: `PLAN.md` §8 row K.

| | |
|---|---|
| Backups taken first | `pre-promo-docuseal-2026-09-15T124719Z.dump` (45 tables) + `…-data-…tgz` (2.8 MB) on the VM |
| Compose change | one line — the image tag. Nothing else touched |
| Gates | D1–D5 + fork smoke **ALL PASS**; `/version` → `3.2.4-ccn.5` |
| Rollback | still one command, still clean — re-verified `db/` is untouched by `.4..5` and by `3.2.4..ccn` |

Two things worth carrying forward:

- **Reminders are dormant on production, and that was verified rather than assumed.** `/api/ccn/reminders/due`
  answers 200 there now (it 404'd on `.4`), so the old "404 proves it is off" check no longer means anything.
  What proves it is off: `CCN_REMINDERS_ENABLED` is `nil` and `Sidekiq::Cron::Job.all` is **empty** on the box.
  Setting that flag is what starts automated mail to real signers — an explicit decision, never a side effect.
- **`prod-gates.sh` D3 was wrong and is now fixed.** It read Coolify's service status once, straight after the
  deploy, and got a stale `"exited"` while the app was already serving 200s on the new tag — i.e. it advised
  rolling back a healthy production service. It now retries for two minutes before calling it a failure.

Still owed by hand, none of them automatable: D6 admin login, D7 one real signature request end to end, and
the one real reminder in a mailbox that staging could never deliver.

## Post-release defect — the reminder sweep was never scheduled (found 2026-09-15, fixed in `3.2.4-ccn.6`)

Turning reminders on in production exposed a defect that had shipped in `.5` and had been sitting unnoticed on
staging for a day: **`config/initializers/zz_ccn_reminders.rb` guarded the registration with
`Sidekiq.server?`**, which reads `defined?(Sidekiq::CLI)`. This image never loads the CLI — Sidekiq runs
**embedded inside Puma** (`lib/puma/plugin/sidekiq_embed.rb` → `Sidekiq.configure_embed`; `ps` in the
container shows puma and nothing else). So the guard was false in every process and the schedule was
installed nowhere. Evidence, not inference: with `CCN_REMINDERS_ENABLED=true` on staging since the day
before, `Sidekiq::Cron::Job.all` read from Redis was `[]`.

The sweep therefore only ever ran when someone called `POST /api/ccn/reminders/run` by hand — which is
exactly what the S4 gate does, which is why the gate passed. **A green gate on the endpoints said nothing
about the scheduler**, and nothing else was checking it.

Fixed by registering through `Sidekiq.configure_server` + `config.on(:startup)`. That seam works in both
deployment shapes because **Sidekiq 8 records every `configure_server` block in `@config_blocks` and replays
them inside `configure_embed`** (read it in the gem: `sidekiq.rb:109`), and `:startup` is fired by the puma
plugin after it has waited for Redis — which an `after_initialize` at Rails boot could not promise.
`spec/jobs/ccn_send_submitter_reminders_job_scheduling_spec.rb` covers it with `Sidekiq.server?` stubbed
**false**, the condition `.5` got wrong.

Worth generalising: **sidekiq-cron's own poller survives embedded mode for the same reason** — the gem does
its `Sidekiq::Launcher.prepend` inside a `configure_server` block, which gets replayed too. So the poller was
always there; only the job was missing.

## Post-release defect 2 — reminders chased a viewer (found 2026-09-15 by Luciano, fixed in `3.2.4-ccn.6`)

Turning reminders on meant looking at who production would actually mail, and the single pending recipient
there turned out to be **in copy, not a signatory**: no field of her own on a letter both signatories had
already signed. Luciano caught it ("not a signer, but a viewer only, nothing to remind of").

The due rule skipped completed, declined, bounced, opted-out, archived and expired — but never asked whether
the person had anything to do. **A viewer never reaches `completed_at`, because there is nothing to
complete**, so they would have been chased at every stage for ever.

Upstream already models exactly this and uses the same word: `Submissions::CreateFromSubmitters
#assign_submitters_is_viewer` writes `is_viewer` onto any `template_submitters` entry that owns no field, and
`Submitter#viewer?` reads it (it was already `true` on the production record). `Ccn::Reminders.due_row` now
returns on `nothing_to_sign?`, which checks that flag first and falls back to counting the submitter's fields
for submissions created before the flag existed.

Two things this exposed beyond the rule itself:

- **The spec helper was building unrealistic records.** `submitter_sent` gave each submitter a random uuid,
  matching no `template_submitters` entry and therefore no field — which is not how DocuSeal builds them (see
  the `:with_submitters` trait). Every reminder example had been asserting against a shape that cannot occur.
  It now takes the submission's own uuid, and `viewer_sent` covers the new case flagged and unflagged.
- **The S4 gate now creates a viewer** and asserts it is never listed as due, next to the new sidekiq-cron
  assertion. The two ways this feature can quietly misbehave — mailing the wrong person, or scheduling
  nobody at all — are now both gated.

Consequence worth knowing: **production currently has nobody to remind.** Submission 4 is fully signed bar
the viewer, and the only other pending submitter is declined and archived. Switching the schedule on is a
no-op today, which is correct — and it means the "one real reminder in a mailbox" item stays open until a
genuine unsigned document is outstanding.
