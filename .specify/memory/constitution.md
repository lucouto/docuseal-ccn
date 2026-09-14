# docuseal-ccn Constitution

Fork of DocuSeal 3.2.4 (AGPL-3.0 + `LICENSE_ADDITIONAL_TERMS`) run by Communauté du Chemin Neuf. The fork
exists so that Claude Code and CCN staff can drive every DocuSeal function through the API, feed documents in
by any route (PDF, DOCX, HTML, text tags) and use the "Pro" features the upstream open-source build gates off.

## Core Principles

### I. Legally signed documents come first (NON-NEGOTIABLE)
Code on the signing, result-PDF and audit-trail paths (`lib/submitters/*`, `lib/submissions/generate_*`,
`lib/pdf_utils.rb`, `lib/pdfium.rb`) is never modified. New behaviour is added around it. Anything a signer
can influence is bounded before it is evaluated (see `config/initializers/zz_ccn_dentaku.rb`) and fails as a
translated HTTP 422, never as a 500 or a silent wrong value.

### II. Upstream is the contract
The public API is `docs/openapi.json` as published by upstream: every documented operation is implemented to
that schema so the official CLI, SDKs and Claude Code work unchanged. `spec/requests/openapi_contract_spec.rb`
pins the gap. Fork-only functions live under `/api/ccn/...` and are documented in `docs/openapi-ccn.json`.

### III. Rebase-cheap by construction
Prefer new files (`lib/ccn/*`, `app/controllers/api/ccn_*`, `config/initializers/zz_ccn*`) and the empty
hook partials over edits to upstream files. Every touched upstream file is listed in `CCN-CHANGES.md` with the
reason. Migrations are additive only. No new gems without a pinned version and a line in `CCN-CHANGES.md`.

### IV. Verified independently, gated per stage
Every change ships with request specs; CI (rubocop, erb_lint, eslint, brakeman, rspec) must be green; a
diff-only reviewer subagent reads the change before it is tagged; a stage is promoted to staging only when
its `FORK-PLAN.md` §10 gate passes on the live instance, and to production only when Luciano confirms.
Attempts are capped at three per failing item; state lives in `LOOP-STATE.md` and `tasks.md`.

### V. Licence and attribution
The DocuSeal attribution stays on the signing page (AGPL §7(b) additional term); the fork's source stays
public and linked from every page (AGPL §13); the image is pinned (`ghcr.io/lucouto/docuseal-ccn:<tag>`),
never `:latest`. `MULTITENANT=true` is cloud mode, never set.

## Operating Constraints
- Staging (`docuseal-staging.cheminneuf.community`) never e-mails and never touches production data;
  production stays on the stock image until an explicit promotion decision.
- Secrets are referenced as `$VAR`, never printed or committed.
- Server-side conversions run through the Gotenberg sidecar (`GOTENBERG_URL`), internal network only,
  pinned version; a sidecar failure is a clear 422, never a silent fallback.
- Ruby behaviour is verified on the image's Ruby (`ruby:4.0.5-alpine` container on the VM), not on the
  local Ruby 2.6.

## Workflow
Spec-Kit per stage (`specs/NNN-*/spec.md → plan.md → tasks.md`), implementation task by task with a request
spec per task, CI + reviewer before tagging `3.2.4-ccn.N`, staging deploy with `staging-deploy-tag.sh`, live
gate scripts, then `LOOP-STATE.md` and memory updated.

## Governance
This constitution supersedes ad-hoc practice for the fork. Amendments are recorded here with a version bump
and mirrored in `FORK-PLAN.md`. Reviews check compliance with Principles I–V explicitly.

**Version**: 1.0.0 | **Ratified**: 2026-09-14 | **Last Amended**: 2026-09-14
