---
description: "Task list for Stage 3 — everything else by API"
---

# Tasks: Everything else by API

**Input**: Design documents from `specs/002-everything-by-api/` (plan.md, spec.md, research.md, data-model.md, contracts/README.md)

**Tests**: a request spec per controller and per MCP tool is part of every task (constitution IV). CI must stay green after every phase; a diff-only reviewer reads phases 1–5 before phase 6 starts and phases 6–7 before the gate.

**Organization**: phase 1 is plumbing; phases 2–5 map to US1–US4 (REST); phase 6 is US5 (MCP); phase 7 is US6 (docs); phase 8 is the gate and release.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [ ] T001 `lib/ccn/admin_invalid.rb` (`Ccn::AdminInvalid < StandardError`) and `lib/ccn/admin_errors.rb` (concern: `rescue_from Ccn::AdminInvalid, ActiveRecord::RecordInvalid, Ccn::NotSupportedYet → 422 {error}`; `ActiveRecord::RecordNotFound → 404 {error: not_found}`) + locale keys en/fr in `config/locales/ccn/ccn.yml`: `ccn_user_exists`, `ccn_self_change_refused`, `ccn_reset_already_sent`, `ccn_user_archived`, `ccn_unknown_webhook_event`, `ccn_invalid_url` (exists), `ccn_no_completed_submitter`, `ccn_unknown_setting`, `ccn_invalid_setting_value`, `ccn_unknown_preference`, `ccn_folder_depth`, `ccn_default_folder_immutable`, `ccn_folder_not_empty`, `ccn_version_documents_missing`, `ccn_no_documents`, `ccn_too_many_pages`, `ccn_not_found`
- [ ] T002 Routes: `scope 'ccn' do … end` inside `namespace :api` in `config/routes.rb` (users, webhooks + secret/events/resend/test, account_configs (`param: :key`, constraint allowing dots? keys are `[a-z_]+`), template_folders, templates → versions (+ restore) and detect_fields), all with `controller:` and `as: 'ccn_…'`; register in `CCN-CHANGES.md`
- [ ] T003 [P] `spec/support/openapi_contract.rb`: `OpenapiContract.load(path)` / `spec(path = SPEC_PATH)` so a second document can be validated; existing spec unchanged in behaviour

## Phase 2: Users (US1)

- [ ] T004 `lib/ccn/manage_users.rb` — `list(account, status:)`, `invite(account, actor, attrs, send_email:)`, `update(user, actor, attrs)`, `archive(user, actor)`, `send_reset_password(user)`, `serialize(user)` per data-model.md (guards, reactivation, mail/job side effects)
- [ ] T005 `app/controllers/api/ccn_users_controller.rb` (index/create/show/update/destroy/reset_password; `include Ccn::AdminErrors`; explicit `authorize!(:manage, User)`) + `spec/requests/ccn_users_spec.rb` (list filters and shape without uuid/tokens; invite queues `UserMailer` unless `send_email: false`; duplicate active 422; archived reactivated; update + `SendConfirmationInstructionsJob` on e-mail change; self guards 422; archive; reset throttle 422; foreign id 404; wrong token 401)

## Phase 3: Webhooks (US2)

- [ ] T006 `lib/ccn/manage_webhooks.rb` — `list`, `create`, `update`, `destroy`, `serialize`, `reveal`, `events(webhook, status:)`, `serialize_event`, `resend(webhook, uuid)`, `test(webhook, account)` per data-model.md
- [ ] T007 `app/controllers/api/ccn_webhooks_controller.rb` + `spec/requests/ccn_webhooks_spec.rb` (create with defaults; invalid event / url 422 naming the value; secret write-only + `secret_key` + reveal endpoint; update replaces secret whole / `{}` clears; events list newest first with attempts and `status` filter; resend job class + args; test job or 422 without completed submitter; delete; foreign 404)

## Phase 4: Account configs (US3)

- [ ] T008 `lib/ccn/manage_account_configs.rb` — `KEYS` typed table (data-model.md), `list(account)`, `get`, `set(account, key, value)`, `reset`, `serialize` + `spec/lib/ccn/manage_account_configs_spec.rb` (each type coerced/refused; members filtered; reminders durations validated; blank → delete; encrypted keys unknown; defaults evaluated)
- [ ] T009 `app/controllers/api/ccn_account_configs_controller.rb` (index/show/update/destroy, `authorize!(:manage, AccountConfig)`) + `spec/requests/ccn_account_configs_spec.rb` (list has every key with type/default; set boolean/string/object; wrong type 422; unknown and `action_mailer_smtp` 422 without touching `EncryptedConfig`; delete; `enable_mcp` toggle)

## Phase 5: Templates (US4)

- [ ] T010 `lib/ccn/template_preferences.rb` — `KEYS`, `NESTED`, `apply!(template, preferences, account)` + `spec/lib/ccn/template_preferences_spec.rb`; hook in `app/controllers/api/templates_controller.rb#update` (one line + `ccn_preferences_params`), registered in `CCN-CHANGES.md`; request examples in `spec/requests/ccn_template_admin_spec.rb` (set/read back via `GET /api/templates/{id}`; `null` deletes; unknown 422; `default_expire_at` timezone; upstream response unchanged; `template.updated` job count unchanged)
- [ ] T011 [P] `lib/ccn/manage_folders.rb` + `app/controllers/api/ccn_template_folders_controller.rb` + examples (list with `full_name`/`templates_count`; create two levels / three → 422; rename; default immutable; archive empty / non-empty 422)
- [ ] T012 [P] `lib/ccn/template_version_restore.rb` + `app/controllers/api/ccn_template_versions_controller.rb` + examples (list newest first; snapshot idempotent; show serialized documents; restore replaces `DATA_FIELDS` after a pre-snapshot; missing document → 422 no change; dynamic documents → not supported)
- [ ] T013 [P] `lib/ccn/detect_template_fields.rb` + `app/controllers/api/ccn_template_detect_fields_controller.rb` + examples (detector stubbed to yield fixtures; grouped response; `attachment_uuid`/`page` selection; `apply: true` adds fields under the first submitter and skips duplicates; no documents 422; > 30 pages 422)

## Review 1 (after phase 5)

- [ ] T014 Diff-only reviewer on phases 1–5 (delta from `83470548`); findings fixed; CI green

## Phase 6: MCP tools (US5)

- [ ] T015 `Ccn::CreateSubmissionFromDocuments.create!(user:, params:, format:)` — the transient → create → detach → discard sequence moved out of `Api::CcnSubmissionsDocumentsController` (which now calls it) so MCP shares it; `lib/ccn/mcp_tool_errors.rb` (concern: the admin + ingestion error table → `render_tool_error`)
- [ ] T016 Eight `app/controllers/mcp/ccn_*_controller.rb` with `SCHEMA` + `call` (data-model.md arguments): `create_template_from_documents`, `update_template_documents`, `merge_templates`, `create_submission_from_documents`, `manage_users`, `manage_webhooks`, `account_config`, `set_template_preferences`; registered in `app/controllers/mcp_controller.rb` `TOOL_CONTROLLERS` (`CCN-CHANGES.md`)
- [ ] T017 `spec/requests/ccn_mcp_spec.rb` — `McpToken` + `enable_mcp`; `tools/list` = 13 tools with schemas; one `tools/call` per fork tool (Gotenberg stubbed for docx/html); invalid argument → `isError: true` with the REST message; MCP disabled → 403; foreign template → tool error "Not found"

## Phase 7: Documentation (US6)

- [ ] T018 `docs/openapi-ccn.json` — 29 operations of contracts/README.md in upstream's style (3.1.0, `AuthToken`, inlined schemas, `examples`), `x-ccn-extends` on `PUT /templates/{id}`
- [ ] T019 `spec/requests/ccn_openapi_contract_spec.rb` — every operation routable; one request per operation with a conforming 200 (factories + stubs), reusing `OpenapiContract.validate`
- [ ] T020 [P] `CCN-CHANGES.md` (new files + the three upstream edits), quickstart verified against the spec examples

## Review 2 (after phase 7)

- [ ] T021 Diff-only reviewer on phases 6–7; findings fixed; CI green

## Phase 8: Gate + release

- [ ] T022 `staging-s3-check.sh` (operations directory): SC-002 sequence (user, webhook, folder, preference, config → read back → revert, account state unchanged) + SC-003 (`tools/list` with `$DOCUSEAL_MCP_TOKEN` when set; skipped with a note otherwise) + no-500 assertion
- [ ] T023 Tag `3.2.4-ccn.4`, image build, `staging-deploy-tag.sh 3.2.4-ccn.4`, gates S1 + bounds + S2 + S3
- [ ] T024 `CLAUDE.md` (operations directory) cheat sheet rewritten from `docs/openapi.json` + `docs/openapi-ccn.json`; `LOOP-STATE.md`; memory

## Dependencies

- Phase 1 → everything. Phases 2–5 independent of each other ([P] within phase 5). Phase 6 needs 2–5 (services). Phase 7 needs 2–6. Phase 8 needs 7 and review 2.
