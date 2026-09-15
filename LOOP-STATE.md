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
| 4 Account logo (US2) | T012–T015 | **done** — static checks green, rspec on CI |
| 5 Roles (US3) | T016–T018 | not started |
| Review B | T019 | not started |
| 6 Documentation | T020–T022 | not started |
| 7 Bulk list (US4, optional) | T023–T024 | not started |
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
- **Needs validation (Luciano)**: nothing yet.
- **Blocked**: nothing yet.
