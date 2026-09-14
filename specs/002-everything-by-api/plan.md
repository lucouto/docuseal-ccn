# Implementation Plan: Everything else by API

**Branch**: `ccn` | **Date**: 2026-09-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-everything-by-api/spec.md`

## Summary

Stage 3 of FORK-PLAN.md turns the functions that are UI-only even in DocuSeal Pro into REST operations under
`/api/ccn/...` (users, webhooks, account settings, template folders, template versions, field detection), lets
`PUT /api/templates/{id}` write template preferences, mirrors the same functions as MCP tools, and publishes
`docs/openapi-ccn.json` with a contract spec. Every operation is a thin `Api::Ccn*Controller` over a
`Ccn::Manage*` service module that the MCP tool controllers share; behaviour, allow-lists and guards are copied
from the UI controllers they replace (research.md, inventory of 2026-09-14).

## Technical Context

**Language/Version**: Ruby 4.0.5 / Rails 8.1 (upstream 3.2.4); no front-end change

**Primary Dependencies**: upstream models and service modules only (`User`, `WebhookUrl`, `WebhookEvent`,
`AccountConfig`, `TemplateFolder`, `TemplateVersion`, `TemplateFolders`, `TemplateVersions`, `WebhookUrls`,
`Templates::DetectFields`, `UserMailer`, Devise); Stage 2 modules for the MCP ingestion tools; no new gem

**Storage**: PostgreSQL, unchanged schema (no migration)

**Testing**: RSpec request specs per controller (`spec/requests/ccn_users_spec.rb`, `ccn_webhooks_spec.rb`,
`ccn_account_configs_spec.rb`, `ccn_template_admin_spec.rb`, `ccn_mcp_spec.rb`, `ccn_openapi_contract_spec.rb`),
lib specs for the value coercion tables; the ML detector stubbed in CI; e-mail through the test delivery method

**Target Platform**: Linux/amd64 container on Coolify (staging first)

**Project Type**: Rails monolith (web service + API)

**Performance Goals**: every operation is a few queries; field detection bounded to 30 pages per request
(synchronous); lists paginated (≤ 100)

**Constraints**: no change to `lib/submitters/*`, `lib/submissions/generate_*`, `lib/pdfium.rb`,
`lib/pdf_utils.rb`; upstream files edited: `config/routes.rb` (one `scope 'ccn'` block),
`app/controllers/api/templates_controller.rb` (one hook line + one private method),
`app/controllers/mcp_controller.rb` (eight hash entries); everything client-caused → 422 `{error}` translated
en/fr; no secret in list/show responses; `EncryptedConfig` never touched

**Scale/Scope**: single-tenant instance, a dozen users, a handful of webhooks; 6 REST controllers (~25
operations), 8 MCP tools, ~2 000 lines of new Ruby including specs

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Signing path untouched | ✅ no file under `lib/submitters`, `lib/submissions/generate_*`, `lib/pdfium.rb`, `lib/pdf_utils.rb` is edited; nothing here evaluates signer input |
| II. Upstream is the contract | ✅ upstream `docs/openapi.json` untouched and its contract spec still green; fork operations under `/api/ccn/...` in `docs/openapi-ccn.json` with their own contract spec; the one upstream operation extended (`PUT /templates/{id}`) keeps its response and side effects |
| III. Rebase-cheap | ✅ new files (`app/controllers/api/ccn_*`, `app/controllers/mcp/ccn_*`, `lib/ccn/*`); three upstream edits, each a hook, registered in `CCN-CHANGES.md`; no migration; no gem |
| IV. Verified independently | ✅ request spec per controller and per tool; CI green per phase; diff-only review after the REST phases and after the MCP/docs phases; S3 gate script on staging before tagging |
| V. Licence / attribution | ✅ no UI change; source stays public |

## Project Structure

### Documentation (this feature)

```text
specs/002-everything-by-api/
├── plan.md              # this file
├── research.md          # D1–D12 + verified upstream facts
├── data-model.md        # request/response shapes, allow-lists, coercions
├── quickstart.md        # curl walk-through = the S3 gate script's steps
├── contracts/README.md  # operation table → docs/openapi-ccn.json
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
app/controllers/api/
├── ccn_users_controller.rb                 # /api/ccn/users
├── ccn_webhooks_controller.rb              # /api/ccn/webhooks (+ secret, events, resend, test)
├── ccn_account_configs_controller.rb       # /api/ccn/account_configs
├── ccn_template_folders_controller.rb      # /api/ccn/template_folders
├── ccn_template_versions_controller.rb     # /api/ccn/templates/:template_id/versions (+ restore)
├── ccn_template_detect_fields_controller.rb# /api/ccn/templates/:template_id/detect_fields
└── templates_controller.rb                 # UPSTREAM: + preferences hook (D6)
app/controllers/mcp/
├── ccn_create_template_from_documents_controller.rb
├── ccn_update_template_documents_controller.rb
├── ccn_merge_templates_controller.rb
├── ccn_create_submission_from_documents_controller.rb
├── ccn_manage_users_controller.rb
├── ccn_manage_webhooks_controller.rb
├── ccn_account_config_controller.rb
└── ccn_set_template_preferences_controller.rb
app/controllers/mcp_controller.rb           # UPSTREAM: + 8 TOOL_CONTROLLERS entries
lib/ccn/
├── admin_invalid.rb                        # Ccn::AdminInvalid < StandardError
├── admin_errors.rb                         # concern: rescue table for the admin controllers (422/404)
├── mcp_tool_errors.rb                      # concern: same table → render_tool_error
├── manage_users.rb
├── manage_webhooks.rb
├── manage_account_configs.rb
├── template_preferences.rb
├── manage_folders.rb
├── template_version_restore.rb
├── detect_template_fields.rb
└── create_submission_from_documents.rb     # + create!(user:, params:, format:) shared by REST and MCP
config/routes.rb                            # UPSTREAM: scope 'ccn' inside namespace :api
config/locales/ccn/ccn.yml                  # new keys (ccn_unknown_setting, ccn_unknown_preference, …)
docs/openapi-ccn.json
spec/requests/ccn_users_spec.rb, ccn_webhooks_spec.rb, ccn_account_configs_spec.rb,
              ccn_template_admin_spec.rb, ccn_mcp_spec.rb, ccn_openapi_contract_spec.rb
spec/lib/ccn/manage_account_configs_spec.rb, template_preferences_spec.rb
spec/support/openapi_contract.rb            # SPEC_PATH parameterised (load(path))
```

**Structure Decision**: same as Stage 2 — flat `Api::Ccn*` controllers (an `Api::Ccn` module would shadow
`::Ccn`), flat `Ccn::*` modules with names that do not collide with upstream modules referenced from inside
`Ccn` (`ManageUsers` not `Users`, `ManageFolders` not `TemplateFolders`), MCP controllers as
`Mcp::Ccn*Controller` next to upstream's five.

## Design decisions (summary; rationale in research.md)

1. **Routes**: one `scope 'ccn' do … end` block inside `namespace :api`; `resources` with `controller:` and
   `as: 'ccn_…'`; nested template routes as `resources :templates, only: [], controller: 'ccn_templates', as:
   'ccn_templates' do resources :versions …; post :detect_fields end`.
2. **Authorization**: explicit `authorize!` per action on the loaded record or class; records loaded through
   `current_account` (404 for foreign ids); templates through `Template.accessible_by(current_ability)`.
3. **Services**: `Ccn::Manage*` modules with `list/create/update/…` functions that take indifferent hashes and
   return the serialized hash; `Ccn::AdminInvalid` for client errors; controllers and MCP tools only translate
   HTTP/MCP ↔ hashes.
4. **Serialization** (data-model.md): users without uuid/tokens; webhooks with `secret_key` only; configs with
   `key/value/default/type`; folders with `full_name` and `templates_count`; versions via
   `TemplateVersions.serialize`; detection results grouped by document and page.
5. **Account configs**: typed allow-list table (boolean / string / object with member lists), UI coercions,
   blank → delete; `EncryptedConfig` keys unknown by construction.
6. **Template preferences**: hook in the upstream `update` (one line + one private method), UI allow-list,
   `null` deletes, unknown → 422.
7. **Versions**: restore = pre-snapshot + `DATA_FIELDS` assignment, refused when documents are missing.
8. **Detection**: synchronous JSON, 30-page cap, optional `apply`.
9. **MCP**: eight tools, `SCHEMA` + `call`, registered in `TOOL_CONTROLLERS`, errors as tool errors; ingestion
   tools reuse Stage 2 modules through a shared `create!` for submissions.
10. **Docs**: `docs/openapi-ccn.json` (fork-only, same style), `ccn_openapi_contract_spec.rb`; `CLAUDE.md`
    cheat sheet (operations directory) rewritten from both spec files at release.
11. **Gate**: `staging-s3-check.sh` (operations directory) = SC-002 + SC-003 (`tools/list` via curl with the
    MCP token from the environment); tag `3.2.4-ccn.4` once CI, review and gate pass.

## Phases

| Phase | Content | Verification |
|-------|---------|--------------|
| 1 Setup | routes block, `Ccn::AdminInvalid`, `Ccn::AdminErrors`, locale keys, `openapi_contract.rb` parameterised, `docs/openapi-ccn.json` skeleton | CI green |
| 2 Users (US1) | `Ccn::ManageUsers` + controller + spec | spec: list filters, invite (mail queued / `send_email: false`), reactivate, 422 duplicate, update + reconfirmation job, self guards, archive, reset throttle |
| 3 Webhooks (US2) | `Ccn::ManageWebhooks` + controller + spec | spec: create defaults, invalid event/url 422, secret write-only + reveal, events list + status filter, resend job args, test job, delete |
| 4 Account configs (US3) | `Ccn::ManageAccountConfigs` (+ lib spec) + controller + spec | spec: list with defaults/types, set each type, wrong type 422, unknown/encrypted 422, delete, reminders validation |
| 5 Templates (US4) | `Ccn::TemplatePreferences` hook (+ lib spec), `Ccn::ManageFolders`, `Ccn::TemplateVersionRestore`, `Ccn::DetectTemplateFields` + controllers + spec | spec: preferences coercions/null/unknown, folders CRUD + guards, versions list/snapshot/show/restore/refusal, detection stubbed + apply |
| — Review 1 | diff-only reviewer on phases 1–5 | findings fixed, CI green |
| 6 MCP (US5) | shared `create!`, eight tool controllers, `TOOL_CONTROLLERS`, `Ccn::McpToolErrors`, `ccn_mcp_spec.rb` | spec: `tools/list` has 13 tools; one `tools/call` per fork tool; tool error on invalid input; disabled MCP 403 |
| 7 Docs (US6) | `docs/openapi-ccn.json` complete, `ccn_openapi_contract_spec.rb`, `CCN-CHANGES.md`, quickstart | contract spec green |
| — Review 2 | diff-only reviewer on phases 6–7 | findings fixed, CI green |
| 8 Gate + release | `staging-s3-check.sh`, tag `3.2.4-ccn.4`, deploy, S1 + bounds + S2 + S3 gates, `CLAUDE.md`, `LOOP-STATE.md`, memory | all gates PASS |

## Complexity Tracking

| Item | Why it is needed | Simpler alternative rejected |
|------|------------------|------------------------------|
| Three upstream edits (routes, templates#update hook, TOOL_CONTROLLERS) | routes must live in the `:api` namespace; the `preferences` extension is on an upstream operation; MCP registration is a constant | monkey-patching the constant in an initializer (warnings, fragile) |
| Typed config table (≈30 rows) | the model has no allow-list and the UI's three lists have no types; precise 422s need them | pass-through JSON (would store wrong shapes the UI then cannot read) |
| Shared `create!` for template-less submissions | MCP tool and REST controller must run the identical create → detach → discard sequence | duplicating the sequence in the tool controller |
