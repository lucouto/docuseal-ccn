# Review A — brief for an independent reviewer

**What this is**: the hand-off document for the diff-only review `tasks.md` schedules as **T011 (Review A, after
phase 3)** of Stage 4. Read this file, then read the diff yourself — do not trust this document's own
description of what the code does; verify it. Findings should be the kind that would embarrass the author,
not a restatement of this brief.

## Scope

**Review this and only this**: phases 1–3 of `specs/003-p1-features/tasks.md` (T001–T010) — automated signer
reminders (User Story 1). That is everything from the merge-base below up to and including commit `3e922d0e`
on branch `ccn`.

```bash
cd ~/Projets_apps_github/docuseal-ccn
git diff be6b5933..3e922d0e --stat   # the full file list
git diff be6b5933..3e922d0e          # the full diff
```

`be6b5933` is the tip of Stage 3 (already reviewed and shipped as `3.2.4-ccn.4`). Everything after it is Stage
4 so far: three commits are the Spec-Kit paper trail (`49a47f1c` spec+research, `afce2904` plan+data-model+
contracts+quickstart+checklist, `7c7aeb0e` tasks.md) — skim these for context but they are docs, not code, and
don't need a code review. The four commits that matter are:

- `55c4cfd3` — the actual implementation (phases 1–3).
- `1d9cedbb`, `3e922d0e` — two rounds of CI-driven fixes. **Read these carefully: they touch only spec files
  and one line-wrap in `app/mailers/ccn_submitter_reminder_mailer.rb`. No production logic changed between
  `55c4cfd3` and `3e922d0e`** — the fixes were rubocop style and test-fixture gaps (a fresh `Account` needs a
  `User` before a `Template` can be created under it; `Submitter` has no default `uuid`; `Accounts.
  can_send_emails?` is `false` by default in the test environment). If you want to sanity-check that claim
  yourself: `git diff 55c4cfd3..3e922d0e -- app/ lib/ config/` should be one hunk.

**Out of scope**: phases 4–8 (logo, roles, docs, optional bulk, gate+release) don't exist yet — don't review
code that isn't there, and don't flag `CCN-CHANGES.md` as stale for Stage 4 (it's genuinely not updated yet;
that's `tasks.md` T022, scheduled for phase 6, not an oversight in phases 1–3).

## Context you need

- **Constitution**: `.specify/memory/constitution.md`. Principle I (signing path untouched) and Principle III
  (rebase-cheap, minimal upstream edits, no migration) are the two most likely to be violated by accident.
  Check: `git diff be6b5933..3e922d0e --stat -- lib/submitters/ lib/submissions/generate_* lib/pdf_utils.rb
  lib/pdfium.rb` must be empty. Check: no `db/migrate/` file was added.
- **Design decisions this code must match**: `research.md` D1–D6 (scheduler, durations, due rule, run lock,
  mailer, API observability) and `spec.md`'s FR-001 through FR-005 and User Story 1's acceptance scenarios.
  `data-model.md`'s "Reminders" section is the precise contract (due-rule pseudocode, the `run` JSON shape,
  the mailer's resolution order) — treat it as the spec for this diff, not just background reading.
- **CI state**: as of this brief, CI had gone through two failed rounds (rubocop + missing test fixtures,
  both fixed) and a third push (`3e922d0e`) was in flight. Check current status before concluding "CI green"
  either way: `gh run list -R lucouto/docuseal-ccn --json headSha,status,conclusion -L 3`. If it's still red on
  something other than what this brief describes as already fixed, that is itself a finding.

## Where to look harder

These are the places most likely to hide a real bug, in the author's own judgment — spend disproportionate
time here rather than spreading evenly across the diff:

1. **`lib/ccn/reminders.rb` — the due-rule SQL** (`candidates`): the range `(min_due - LATE_GRACE)..max_due` is
   built from `durations.values.max`/`.min` across whichever of the three stages are configured. If only stage
   1 and stage 3 are configured (stage 2 left blank), does the range still correctly bound stage 3 candidates?
   Walk through the arithmetic by hand for that case, not just the common "all three configured, increasing"
   case the tests exercise.
2. **The late-expiry boundary** (`now > due_at + LATE_GRACE`) — is this the right side of the boundary at
   exactly `sent_at + duration + 7.days`? An off-by-one here silently changes whether the last possible moment
   of a reminder fires or is skipped. Cross-check against `spec.md`'s SC-001 and FR-001's "not due any more
   when `now > sent_at + duration_k + 7 days`" wording.
3. **The Redis lock** (`acquire_lock!`/`release_lock!` + the `ensure` in `run`): trace every exit path of
   `run` — does the lock always get released, including when `deliver!` raises inside `deliver_due`'s loop
   (e.g. `Submitters::ValidateSending::InvalidEmail`)? If a single delivery raises, does the whole run abort
   without releasing the lock, leaving it held for the full 14-minute TTL? Decide whether that's acceptable
   (rare, self-healing after TTL) or worth a `rescue` inside the loop — this was a judgment call, not
   something exhaustively tested.
4. **`CcnSubmitterReminderMailer` vs `SubmitterMailer#invitation_email`**: the resolution order is deliberately
   simplified (no `email_message`/per-submitter-uuid override, which the invitation mailer has and the
   reminder mailer does not need per `spec.md`). Confirm that simplification is actually safe — i.e. that
   nothing in `Submitters::ValidateSending`, `build_submitter_reply_to`, or `from_address_for_submitter`
   (all reused, unmodified, from `SubmitterMailer`) implicitly assumes the calling context set an
   `@email_message` or similar ivar this mailer never sets.
5. **`Api::CcnRemindersController#run`**: `Ccn::DocumentParams.boolean(params[:dry_run])` — confirm this
   actually defaults to `false` when the param is absent (it should, via `ActiveModel::Type::Boolean#cast(nil)
   == true` being `false`), and that a malformed value (e.g. `dry_run: "banana"`) degrades to `false` rather
   than raising or silently becoming `true`.
6. **The two UI view partials** (`notifications_settings/_reminder_banner.html.erb`,
   `templates_preferences/_submitter_invitation_reminder_email_collapse.html.erb`): these have **no request or
   system spec** — they were hand-verified against the ERB structure of the upstream partials they mirror
   (`_signature_request_email_form.html.erb`, `_submitter_documents_copy_email_form.html.erb`) but never
   actually rendered. If you can spin up the app (or at least `render_views` a request spec that hits
   `GET /settings/notifications` and the template preferences page), do it — this is the single biggest gap
   in phases 1–3's own test coverage. If you can't render them, at minimum check every `f.fields_for`/
   `ff.field_name` call binds to a real attribute of the `Struct.new(...)` object built two lines above it,
   and that the `id`s referenced by `button_tag ... form:` and the reset `button_to` actually match the
   `form_for ... html: { id: ... }` they target.
7. **Test-environment discoveries baked into the specs** (`Accounts.can_send_emails?` false by default,
   `Submitter` needs an explicit `uuid`, `Account#default_template_folder` needs a `User` to exist first): these
   are documented in project memory (`docuseal-fork-plan.md`, "Reusable lessons..." paragraph) as generalizable
   facts about this codebase's test environment — but double check they're *actually* generalizable and not a
   symptom of something more specific being subtly wrong in how these tests build their fixtures.

## What NOT to flag

- Missing MCP tool for reminders — deliberate (research D6: "running reminders from a model transcript is not
  wanted").
- `CCN-CHANGES.md` not updated for Stage 4 yet — scheduled for phase 6 (T022).
- No migration — correct; nothing new is stored, `AccountConfig`/`SubmissionEvent` rows already exist.
- The reminder durations UI form (`_reminder_form.html.erb`) itself — untouched, it already worked before this
  stage; only `_reminder_banner.html.erb` (the e-mail *template* form) is new.

## Reporting format

One finding per line where possible: `file:line — severity (HIGH/MEDIUM/LOW) — the problem — the concrete
failure scenario (what input/state produces a wrong result) — suggested fix`. Group by phase/file. State
plainly if you found nothing beyond nitpicks — a clean report is a valid, useful outcome; don't manufacture
findings to justify the review's cost. Do not fix anything yourself; this is diff-only review, not implement.
