# Review B — brief for an independent reviewer

**What this is**: the hand-off document for the diff-only review `tasks.md` schedules as **T019 (Review B,
after phase 5)** of Stage 4. Read this file, then read the diff yourself — do not trust this document's
description of what the code does; verify it. Findings should be the kind that would embarrass the author,
not a restatement of this brief.

## Scope

**Review this and only this**: phases 4–5 of `specs/003-p1-features/tasks.md` (T012–T018) — the account logo
(User Story 2) and the editor/viewer roles (User Story 3).

```bash
cd ~/Projets_apps_github/docuseal-ccn
git diff 822e77bb..f2a54e47 --stat   # the full file list
git diff 822e77bb..f2a54e47          # the full diff
```

`822e77bb` is the tip of phase 3 (reminders), already covered by Review A. Three commits are in scope:

- `7ff04219` — phase 4, the account logo (US2).
- `74df2d46` — phase 5, the roles (US3).
- `f2a54e47` — the CI fix for phase 4 (the API takes no multipart upload; the settings page gained the
  upload request spec instead).

**Out of scope**: phases 6–8 (docs, the optional bulk list, gate + release) don't exist yet. Reminders
(phases 1–3) were reviewed as Review A — only look at them where phase 4/5 changed their behaviour (the
reminders endpoints appear in the roles matrix, and the mailer layout now renders a partial above every
e-mail body, the reminder's included).

## Context you need

- **Constitution**: `.specify/memory/constitution.md`. Principle I (signing path untouched) and Principle III
  (rebase-cheap, minimal upstream edits, no migration) are the ones most likely to be broken by accident.
  Check: `git diff 822e77bb..f2a54e47 --stat -- lib/submitters/ lib/submissions/generate_* lib/pdf_utils.rb
  lib/pdfium.rb db/migrate/` must be empty.
- **Principle V (licence)** matters more in this diff than in any other in the fork: the logo replaces the
  DocuSeal *mark* on signer-facing pages. Verify that `shared/_attribution`, `shared/_powered_by`,
  `shared/_mailer_attribution` and `shared/_email_attribution` are untouched, and that both the page footer
  and the e-mail footer still carry the attribution with a logo attached.
- **Design of record**: `research.md` D7–D10, `data-model.md` sections "Account logo" and "User role" (the
  precise contract — treat it as the spec for this diff), `spec.md` FR-006 through FR-009 and User Stories
  2 and 3 with their acceptance scenarios, and SC-003/SC-004.
- **CI state**: green expected on `f2a54e47`; confirm before you start:
  `gh run list -R lucouto/docuseal-ccn --json headSha,status,conclusion -L 3`. Red on anything this brief
  does not describe as known is itself a finding. rubocop, erb_lint and brakeman were run locally on the
  whole tree and are clean; **rspec could not be run locally** (no PostgreSQL, Redis or libvips on the
  author's machine — see `LOOP-STATE.md`), so every spec in this diff has only ever run on CI.

## Where to look harder

Spend disproportionate time here rather than spreading evenly across the diff.

1. **The two authorization gates that moved** (`app/controllers/api/ccn_users_controller.rb`,
   `app/controllers/mcp/ccn_manage_users_controller.rb`). This is the highest-stakes change in the diff and
   the one the author is least sure is *complete*. The reasoning: every role must be able to `manage` their
   own `User` record, because `ProfileController` does `authorize!(:manage, current_user)`; a CanCan
   **class-level** check cannot evaluate that rule's `id:` condition (`Rule#matches_non_block_conditions`
   returns `@base_behavior` when the subject is a Class), so `can?(:manage, User)` answered **true** for an
   editor, and both controllers gated on exactly that — an editor could have listed and invited users,
   administrators included. Both now authorize `:manage` on `current_account`.
   **Verify the reasoning yourself in the installed cancancan**, and then go looking for the same shape
   elsewhere: any `authorize!(:manage, <Class>)`, `authorize_resource`, or `load_and_authorize_resource` whose
   subject class also appears in `own_records_rules` (`User`, `UserConfig`, `EncryptedUserConfig`,
   `AccessToken`, `McpToken`). `app/controllers/mcp_settings_controller.rb`
   (`load_and_authorize_resource :mcp_token, parent: false`) and
   `app/controllers/encrypted_user_configs_controller.rb` are the two the author looked at and judged safe
   *because their behaviour is unchanged from before this stage* — that is a weaker argument than "a viewer
   cannot do anything harmful there", and it deserves a second opinion.
2. **Does an invalid logo leave anything behind?** `Ccn::AccountLogo#ccn_logo_format` validates during the
   save that attaches. Trace what ActiveStorage has already done by then: `change.blob` triggers
   `build_after_unfurling` (checksum, byte_size, identified content type) — has anything been written to the
   storage service or to `active_storage_blobs` before the validation runs, and if the save fails, is there
   an orphan blob row or an orphan file? The specs assert the *account* has no logo attached; they do not
   assert `ActiveStorage::Blob.count`.
3. **The io rewinding in `ccn_detected_content_type`.** The validation reads the attachable to get the magic
   bytes and rewinds in an `ensure`. Confirm the upload that follows still stores the *whole* file: is the
   checksum computed before or after this read, and is `ActionDispatch::Http::UploadedFile`'s delegation to
   its tempfile actually rewound by `io.rewind` there? One spec asserts the stored bytes equal the uploaded
   bytes for a PNG — decide whether that is enough or whether a truncation could pass it.
4. **`Ccn::AccountLogo.account_for(@submitter, @submission, @template)`** — a shared partial reaching for the
   controller's instance variables. The ivars differ by page (`@submitter` is a `Submitter` on `/s/:slug` but
   a **`Submission`** on the start form, `app/controllers/start_form_controller.rb:20`). Walk every view that
   renders `submit_form/_docuseal_logo` or `start_form/_docuseal_logo` — `submit_form/{show,completed,
   declined,expired,archived,awaiting,delegated,email_2fa}`, `start_form/{show,completed,private,error,
   email_verification}`, `send_submission_email/success` — and find one where the account resolves to `nil`
   (the DocuSeal mark appears for an account that has a logo) or, worse, to the **wrong account**.
5. **The mailer layout renders the logo above *every* e-mail**, not only the ones a signer receives:
   `UserMailer` (staff invitations), `SettingsMailer` (which sets no `@current_account` at all) and Devise's
   password-reset mail all use `layouts/mailer.html.erb`. `spec.md` scenario 3 specifies submitter e-mails;
   scenario 5 keeps the DocuSeal identity on the application's own *pages* and says nothing about staff
   e-mails. Decide whether the broader behaviour is right, and confirm `SettingsMailer` does not break
   (`@current_account` nil → the partial must render nothing).
6. **`Ccn::LastAdminGuard` under concurrency and on the paths the specs do not cover.** `ccn_another_active_admin?`
   is a plain `exists?` with no lock: two simultaneous requests each demoting one of the last two
   administrators both see the other and both succeed. Judge whether that matters here (single instance, a
   dozen users) or whether it needs a note. Also check the guard cannot fire where it should not: on
   `User#update` from Devise's own callbacks (`trackable` writes `last_sign_in_at` on every sign-in — does
   that touch `role`/`archived_at`/`account_id`? if not, confirm the guard costs no query there), and on
   `Account#destroy`'s `dependent: :destroy` cascade over users.
7. **The role matrix against the real controllers, not the ability spec.** `spec/lib/ability_spec.rb` asserts
   the rules; `spec/requests/ccn_roles_spec.rb` asserts eight or so endpoints. The gap in between is every
   *other* controller. Pick the ones a viewer reaching for them would be most damaging —
   `submitters_controller` (edit/update), `submissions_unarchive_controller`, `templates_restore_controller`,
   `templates_clone_controller`, `submitters_resubmit_controller`, `submissions_resend_email_controller`,
   `templates_share_link_controller` — and check each resolves the way the matrix in `data-model.md` says.
   An editor being able to *resend* is intended; a viewer being able to is not.
8. **`Ccn::DocumentParams.decode` grew an optional `param:`** (`lib/ccn/document_params.rb`). It is used by
   Stage 2's ingestion endpoints. Confirm every existing call site produces byte-identical messages to before
   (`documents[0][file] is not valid base64 (or an https URL)`), and that `file_from` handles the shapes
   `files_from` does — in particular an https URL whose path has no basename, and a `name:` that is entirely
   control characters.
9. **FR-007's "byte-identical attribution".** The spec extracts `<div class="text-center px-2">…</div>` with
   a non-greedy regex and compares two renders. Decide whether that block is really the attribution on every
   page in scope, whether the regex could match something else first, and whether comparing two renders in
   the same example can pass while both are wrong.

## What NOT to flag

- **No MCP tool for the logo or the roles** — deliberate (`data-model.md`, "MCP": `manage_users` already
  accepts the new roles once `User::ROLES` grows, and the logo is a settings-page concern).
- **`CCN-CHANGES.md` and `docs/openapi-ccn.json` not updated for Stage 4** — that is phase 6 (T020, T022),
  scheduled after this review, not an oversight. The same goes for `quickstart.md`.
- **No migration** — correct; the ActiveStorage tables exist and `role` is an existing column.
- **`/api/ccn/template_folders` refusing a viewer on GET** — known and deliberate. `contracts/README.md` says
  "viewer 200 on GET", FR-008 says the 403s must come from the existing `authorize!` calls without controller
  changes; resolved in favour of FR-008, to be noted on the operation in T020. Flag it only if you think that
  resolution is wrong, not as an inconsistency.
- **The API refusing multipart uploads** — upstream's `ApiPathConsiderJsonMiddleware` forces
  `application/json` on every `/api` path; the settings page is the upload route. Not a gap.
- **`can :manage, :mcp` for viewers** — per research D9, every role manages their own MCP token.

## Reporting format

One finding per line where possible: `file:line — severity (HIGH/MEDIUM/LOW) — the problem — the concrete
failure scenario (what input/state produces a wrong result) — suggested fix`. Group by phase/file. State
plainly if you found nothing beyond nitpicks — a clean report is a valid, useful outcome; don't manufacture
findings to justify the review's cost. Do not fix anything yourself; this is diff-only review, not implement.
