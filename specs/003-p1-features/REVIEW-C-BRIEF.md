# Review C — brief for an independent reviewer

**What this is**: the hand-off document for the diff-only review `tasks.md` schedules as **T025 (Review C,
after phases 6–7)** of Stage 4 — the last review before the stage is tagged and gated on staging. Read this
file, then read the diff yourself; do not trust this document's description of what the code does. Findings
should be the kind that would embarrass the author, not a restatement of this brief.

## Scope

**Review this and only this**: phase 6 (documentation, T020–T022), the Review B fixes (T019) and phase 7 —
the optional bulk list, User Story 4 (T023–T024).

```bash
cd ~/Projets_apps_github/docuseal-ccn
git diff 8e98314b..68ad5225 --stat   # the full file list
git diff 8e98314b..68ad5225          # the full diff
```

Four commits are in scope:

- `85213247` — phase 6: `docs/openapi-ccn.json` (29 → 34 operations), the contract spec, `CCN-CHANGES.md`,
  `quickstart.md`, and the Review B brief.
- `eb7af6b9` — the Review B fixes. **Re-review these rather than taking them on trust**: they are changes to
  authorization and to a validation, written in response to a review, and nobody has read them since.
- `ffc29020` — phase 7: `Ccn::SubmissionsLists`, `CcnSubmissionsListsController`, the two views, the specs.
- `68ad5225` — a phase 7 fix the author found while writing this brief: blank rows were dropped before the
  rows were numbered, so a file with an empty line in the middle reported every later row one line early.

**Out of scope**: phases 1–5 (reminders, logo, roles) were covered by Review A and Review B; their outcome
sections in `REVIEW-A-BRIEF.md` and `REVIEW-B-BRIEF.md` record what was found and what was deliberately left.
Phase 8 (the staging gate, the tag) does not exist in the repo yet — `staging-s4-check.sh` lives in the
private ops folder and is not part of this diff.

## Context you need

- **Constitution**: `.specify/memory/constitution.md`. For this diff the ones that bite are II (upstream is
  the contract — `docs/openapi.json` and its contract spec must be untouched) and III (rebase-cheap: phase 7
  should add one upstream hook fill-in and one route, nothing more).
- **The contract for phase 7**: `spec.md` FR-010 and User Story 4's two acceptance scenarios, and
  `data-model.md`'s "Bulk list" section, which fixes the column rules and the response shape.
- **The contract for phase 6**: `contracts/README.md` (the five operations and their tags) and
  `data-model.md`'s request/response shapes for reminders and the logo — the description must match what the
  controllers actually answer.
- **CI state**: expected green on `ffc29020`; confirm before starting
  (`gh run list -R lucouto/docuseal-ccn --json headSha,status,conclusion -L 3`). rubocop, erb_lint and
  brakeman were run locally on the whole tree. **rspec cannot run on the author's machine** (no PostgreSQL,
  Redis or libvips), so every spec here has only ever run on CI.

## Where to look harder

1. **The signed payload in `CcnSubmissionsListsController`.** The preview signs the parsed rows and the
   confirm step verifies them. Attack it: can a user of *this* account make the payload create something they
   could not create through the normal Send form — a submitter on a template they cannot read, values on a
   field that is not prefillable, a field belonging to another template, a submitter uuid that is not one of
   the template's roles? `verify` checks the signature, the purpose and the template id; everything after
   that is fed to `Submissions::NormalizeParamUtils.normalize_submissions_params!` and
   `Submissions.create_from_submitters`. Decide whether those two validate what `verify` does not. Also:
   expiry is one hour — check `signed_id_verifier.verified` really enforces it and returns nil rather than
   raising, because the rescue path assumes nil.
2. **`Ccn::SubmissionsLists.resolve_columns` and `split_role`.** The mapping is the part most likely to be
   quietly wrong. Cases to walk by hand: a template whose *role name contains a colon*; two roles whose names
   differ only by case; a column called exactly `email` on a two-role template (it currently falls to the
   first role — is that the right default, and is it what the hint text tells the user?); a prefillable field
   actually named `email` or `name`; the same column name appearing twice in the header; a header cell that
   is nil or blank in the middle of the row.
3. **Row/line numbering.** Errors are reported to a human holding a spreadsheet, so an off-by-one is a real
   defect. The author already found and fixed one here (`68ad5225`) — rows are numbered before the blank ones
   are dropped. Check the fix rather than the old bug: a header that is itself preceded by blank lines, a
   trailing newline, a CSV whose last line has no newline, and an XLSX where rubyXL yields nil for an empty
   row. Does the reported line match what a spreadsheet application would show in every one of those?
4. **What `parse` reads into memory.** `read_csv` does `file.read` and `read_xlsx` does
   `RubyXL::Parser.parse_buffer(file.read)` — the 5 MB cap is checked first, but a 5 MB XLSX can expand to a
   great deal more in rubyXL. Judge whether the cap plus the 500-row limit is enough, remembering that any
   signed-in editor can reach this endpoint.
5. **The Review B fix in `lib/ability.rb`** (`cannot :create, User` in the editor and viewer branches). Verify
   it does not narrow anything else: `User.accessible_by`, the users list, the profile page, the API token
   and MCP token pages, `/api/ccn/...` for an administrator, and `UsersController#create` for an
   administrator. Confirm rule ordering does what the comment claims — CanCan reads rules newest-first.
6. **The Review B fix in `users/_role_select.html.erb`.** It is now `f.select :role, User::ROLES.map …`.
   Check the partial's other call site (the invite form) still defaults to `admin` — `User#role`'s attribute
   default is what supplies it on a new record — and that an administrator editing *themselves* still sees
   their own role even though `UsersController#update` strips `role` for self.
7. **`docs/openapi-ccn.json` against the controllers.** The contract spec asserts a conforming 200 for each
   operation, which does not check the *rest* of the description. Read the five new operations against
   `Api::CcnRemindersController` and `Api::CcnAccountLogoController`: does `GET /ccn/account_logo` really
   answer 404 and not 422 when there is no logo; is `runReminders`' `skipped` shape right; do the
   `x-ccn-role-note` strings match the role matrix as fixed in phase 5 (in particular the template folders
   note); is the `422` example on each operation one that endpoint can actually produce.
8. **`CCN-CHANGES.md` as a rebase checklist.** Its whole job is that whoever rebases onto the next upstream
   tag can find every edit. Check it against `git diff 3.2.4..ffc29020 --stat` restricted to files that exist
   upstream: is any touched upstream file missing a row? The Gemfile and routes.rb rows were merged into
   existing ones — confirm the merge did not lose what the old row said.

## Review C outcome (2026-09-15)

Review C ran and returned **two HIGH, six MEDIUM and six LOW** findings, and verified clean the things this
brief was least sure of: the `68ad5225` line-numbering fix (re-derived against CSV and rubyXL, including an
XLSX with empty rows), the `fe15a860` correction about `archived_at`, the blast radius of `cannot :create,
User` (a `cannot :create` rule is *not relevant* to `can?(:manage, …)`, so the profile page and the token
pages are untouched), and the signed payload itself — uuids and field uuids can only ever come from *this*
template's roles and *prefillable* fields, which is narrower than the ordinary Send form, not wider.

**Both HIGH findings are fixed**, and both were real:

- `Ccn::SubmissionsLists.read_xlsx` parsed the workbook before any row cap applied, and the 5 MB upload cap
  is on the *compressed* zip. Row XML deflates at better than 200:1, so a 5 MB `.xlsx` could become tens of
  millions of `RubyXL::Cell` objects and take the Puma worker down — reachable by any signed-in editor,
  repeatedly. The declared uncompressed size of the zip is now checked (40 MB) before rubyXL is handed the
  buffer, with a spec that builds such a file.
- `CcnSubmissionsListsController` hardcoded `submitters_order: 'random'`, while upstream's
  `_submitters_order` partial *forces* `preserve_order` for a template that signs in order. On a two-party
  contract sent through the list, the counter-signatory would have been invited before the first party
  signed — the one thing the list could do that the ordinary Send page cannot. It now always preserves.

**MEDIUM — fixed.** The archived-template and `variables_schema` guards upstream's Send page applies are now
applied here too; the creation runs in one transaction, so a rule that only bites on save (a duplicate
address across roles under `validate_unique_submitters`) no longer leaves earlier rows saved and marked sent
while the person is told the send was refused; the CSV reader strips a byte-order mark, sniffs `;` and tab as
well as `,`, and falls back to cp1252 when the bytes are not valid UTF-8 — between them, Excel's "CSV UTF-8"
and a French Windows' default export, which were the two likeliest shapes of the first file anyone uploads.
`runReminders.sent` is documented correctly (on a dry run it is what *would* be sent, not 0);
`CCN-CHANGES.md` gained the missing `send_submission_email_controller.rb` row plus the phase 7 files, and its
two stale rows (the hook partials, the routes) are current.

**LOW — fixed.** A repeated header keeps its first column rather than half-overwriting the preview; a `file`
param that is not a file answers the intended message instead of a 500; `_role_select` adds the user's own
role to the list when it is not one of the three, so an `integration` account is not silently offered as
admin; the "does not promote an editor" spec no longer passes `role:` (it tested nothing against the old
partial); the three `422` examples an endpoint cannot produce are replaced; `data-model.md`'s folders line
now matches the code.

**Recorded, not changed.** The payload stays replayable for its hour: burning a nonce needs a store shared
across a browser's tabs, and the exposure — Back, then clicking Send a second time — is bounded by the same
hour and visible to the person doing it. Worth revisiting if the feature is used at scale. Likewise the
nitpicks: `ccn_list_send` has no plural form, and a role whose name contains a colon or differs from another
only by case cannot be addressed by a column prefix.

## What NOT to flag

- **No preview of a valid file beyond the first five rows**, and no column re-mapping UI — `PREVIEW_ROWS` is
  deliberate and the mapping is by header name, per data-model.md.
- **The Upload list tab not being verified in a browser** — recorded in `LOOP-STATE.md` as needing a manual
  pass on staging; the app cannot be run on the author's machine.
- **`docs/openapi.json` (upstream's) unchanged** — correct; the fork documents its own operations separately.
- **No MCP tool for the bulk list, the logo or the reminders** — deliberate (research D6, data-model.md).
- **The `<h1>DocuSeal</h1>` on the start form next to the account logo** — open question for Luciano, already
  recorded in `REVIEW-B-BRIEF.md`'s outcome section.
- **The three LOW findings Review B recorded rather than fixed** (the guard's unlocked `exists?`,
  `email_host_configured?` under multitenant, staff invitations carrying the logo) — decided, with reasons.

## Reporting format

One finding per line where possible: `file:line — severity (HIGH/MEDIUM/LOW) — the problem — the concrete
failure scenario (what input or state produces the wrong result) — suggested fix`. Group by phase or file,
most severe first. State plainly if you found nothing beyond nitpicks — a clean report is a valid, useful
outcome; do not manufacture findings to justify the review's cost. Do not fix anything yourself; this is
diff-only review, not implement.
