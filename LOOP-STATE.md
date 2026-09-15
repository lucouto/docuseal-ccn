# LOOP-STATE — Stage 4 (specs/003-p1-features)

Read this first on every run. Task list: `specs/003-p1-features/tasks.md` (28 tasks, 8 phases, 3 review
gates). Constitution: `.specify/memory/constitution.md`. Operations cheat sheet: `~/Projets_apps_github/DocuSeal/CLAUDE.md`.

**Scope of this stage**: US1 reminders, US2 account logo, US3 editor/viewer roles, US4 bulk CSV list
(optional, P3). Ends at tag `3.2.4-ccn.5` on **staging**; promotion to production is Luciano's separate
decision and is *not* part of this stage.

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
| Review C | T025 | not started |
| 8 Gate + release | T026–T028 | not started |

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
- **Needs validation (Luciano)**:
  - **The S4 gate cannot be closed in full on staging.** `FORK-PLAN.md` §10 asks for "one real reminder in
    Luciano's mailbox from staging", and the constitution forbids exactly that ("staging never e-mails";
    `staging-compose.yml` deliberately declares no `SMTP_*`). `spec.md` anticipated the clash — SC-002 defers
    the real delivery to "after promotion to production, or on staging if Luciano configures SMTP to his own
    mailbox". Everything else in the S4 gate runs; the delivered e-mail is covered by the mailer spec only.
    Luciano's call: point staging SMTP at his own mailbox for one run, or accept the deferral to promotion.
  - `start_form/_docuseal_logo` keeps upstream's `<h1 class="text-5xl">DocuSeal</h1>` next to the account's
    logo (research D8: the logo replaces the mark, not the wordmark). "CCN logo + DocuSeal" at that size is a
    branding call, not an engineering one. The §7(b) attribution is the footer and is untouched either way.
  - US4's *visual* flow (the Upload list tab, the preview page) has request-spec coverage end to end but has
    never been opened in a browser — no way to run the app on this machine. Worth one manual pass on staging.
- **Blocked**: nothing.
