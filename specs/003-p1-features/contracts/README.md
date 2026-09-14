# Contracts: P1 features — reminders, account logo, editor/viewer roles

Source of truth: `docs/openapi-ccn.json` (extended — fork additions only; upstream `docs/openapi.json`
untouched and its contract spec stays green). `spec/requests/ccn_openapi_contract_spec.rb` gets two more
operations to route and validate.

| # | Method | Path | operationId | Tag |
|---|--------|------|-------------|-----|
| 30 | GET | `/ccn/reminders/due` | listDueReminders | Reminders |
| 31 | POST | `/ccn/reminders/run` | runReminders | Reminders |
| 32 | GET | `/ccn/account_logo` | getAccountLogo | Account |
| 33 | PUT | `/ccn/account_logo` | setAccountLogo | Account |
| 34 | DELETE | `/ccn/account_logo` | deleteAccountLogo | Account |

Every operation: `security: [{ "AuthToken": [] }]`; responses `200` (documented schema) and `422`
(`{ "error": string }`); admins only (`403` for editor/viewer, per the roles ability matrix in
data-model.md).

Role effect on existing operations (no schema change, documented as a note on the affected operations in
`docs/openapi-ccn.json`): `/ccn/users`, `/ccn/webhooks*`, `/ccn/account_configs*` → editor and viewer get
`403`; `/ccn/template_folders*`, `/ccn/templates/{id}/versions*`, `/ccn/templates/{id}/detect_fields` →
editor `200`, viewer `200` on `GET` and `403` on write; the ingestion operations already documented (§1–29 of
Stage 3's table) → editor `200`, viewer `403` on create/update.

No new MCP tool this stage (data-model.md, "MCP" section).

## Already available upstream/fork (no new operation, documented in the cheat sheet)

- `manage_users` MCP tool and `/api/ccn/users` already accept `role`; once `User::ROLES` includes
  `editor`/`viewer` no code changes, only the accepted value set grows.
- `PUT /api/templates/{id}` `preferences.invitation_reminder_email_subject/body` (Stage 3) is the per-template
  override the reminder mailer reads — no new endpoint, just a new reader.
