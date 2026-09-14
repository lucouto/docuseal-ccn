# Specification Quality Checklist: P1 features — reminders, account logo, editor/viewer roles

**Purpose**: Validate specification completeness and quality before planning
**Created**: 2026-09-14
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details leak into user stories (module/gem names appear only in requirements naming the upstream mechanism being filled in)
- [x] Focused on user value: each story names who does what and why (admin sets reminders, signer trusts a branded request, colleague gets scoped access)
- [x] Written for non-technical stakeholders where possible (stories); requirements are for the implementer
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain (design questions resolved in research.md D1–D12)
- [x] Requirements are testable and unambiguous (each names the exact rule, endpoint, hook or ability branch)
- [x] Success criteria are measurable (SC-001..006: exact timing sequence, gate script behaviour, HTML assertions, a role×operation matrix, zero 500s, exact file/no-migration set)
- [x] Success criteria are technology-agnostic where they describe outcomes (SC-001, SC-003 read as user-observable behaviour)
- [x] All acceptance scenarios are defined (4 stories — 3 mandatory + 1 optional —, 24 scenarios)
- [x] Edge cases are identified (backlog burst, no-SMTP staging, resend not restarting the clock, concurrent runs, SVG refusal, missing APP_URL, token scoping per role, last-admin guard, XLSX formulas)
- [x] Scope is clearly bounded (Assumptions section: durations count from initial send, per-user template access is out of scope, bulk is optional and last)
- [x] Dependencies and assumptions identified (staging never e-mails — verified by dry run/report only; `CCN_REMINDERS_ENABLED` staging-only; the P1 set is exactly what Luciano named 2026-09-14)

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria (FR-001..012 each map to at least one acceptance scenario)
- [x] User scenarios cover primary flows (set durations → reminded, upload logo → seen by signers, invite editor/viewer → scoped access, upload list → bulk send)
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification beyond the names of the upstream behaviours/hooks mirrored

## Notes

- This is the checklist Stage 3's own notes asked to re-run: roles (US3) now change who may call every `/api/ccn/...`
  operation from Stage 2/3 — FR-008 and data-model.md's ability matrix are the authoritative answer, and
  Stage 2/3's request specs are unaffected because they all run as an admin token.
- US4 (bulk list) is P3/optional by the spec's own priority; its tasks are written but only executed once
  US1–US3 are green (plan.md phase 7 is separable from the release gate for the mandatory stories if time runs
  short — a judgement call for `tasks.md`/`LOOP-STATE.md` to record, not this checklist).
