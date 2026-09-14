# Contracts: Everything else by API

Source of truth: `docs/openapi-ccn.json` (OpenAPI 3.1, fork additions only; upstream operations stay in
`docs/openapi.json`). `spec/requests/ccn_openapi_contract_spec.rb` asserts every operation below is routable and
that its 200 response validates against the documented schema.

| # | Method | Path | operationId | Tag |
|---|--------|------|-------------|-----|
| 1 | GET | `/ccn/users` | listUsers | Users |
| 2 | POST | `/ccn/users` | inviteUser | Users |
| 3 | GET | `/ccn/users/{id}` | getUser | Users |
| 4 | PUT | `/ccn/users/{id}` | updateUser | Users |
| 5 | DELETE | `/ccn/users/{id}` | archiveUser | Users |
| 6 | POST | `/ccn/users/{id}/reset_password` | resetUserPassword | Users |
| 7 | GET | `/ccn/webhooks` | listWebhooks | Webhooks |
| 8 | POST | `/ccn/webhooks` | createWebhook | Webhooks |
| 9 | GET | `/ccn/webhooks/{id}` | getWebhook | Webhooks |
| 10 | PUT | `/ccn/webhooks/{id}` | updateWebhook | Webhooks |
| 11 | DELETE | `/ccn/webhooks/{id}` | deleteWebhook | Webhooks |
| 12 | GET | `/ccn/webhooks/{id}/secret` | revealWebhookSecret | Webhooks |
| 13 | GET | `/ccn/webhooks/{id}/events` | listWebhookEvents | Webhooks |
| 14 | POST | `/ccn/webhooks/{id}/events/{uuid}/resend` | resendWebhookEvent | Webhooks |
| 15 | POST | `/ccn/webhooks/{id}/test` | testWebhook | Webhooks |
| 16 | GET | `/ccn/account_configs` | listAccountConfigs | Account |
| 17 | GET | `/ccn/account_configs/{key}` | getAccountConfig | Account |
| 18 | PUT | `/ccn/account_configs/{key}` | setAccountConfig | Account |
| 19 | DELETE | `/ccn/account_configs/{key}` | resetAccountConfig | Account |
| 20 | GET | `/ccn/template_folders` | listTemplateFolders | Templates |
| 21 | POST | `/ccn/template_folders` | createTemplateFolder | Templates |
| 22 | PUT | `/ccn/template_folders/{id}` | renameTemplateFolder | Templates |
| 23 | DELETE | `/ccn/template_folders/{id}` | archiveTemplateFolder | Templates |
| 24 | GET | `/ccn/templates/{id}/versions` | listTemplateVersions | Templates |
| 25 | POST | `/ccn/templates/{id}/versions` | createTemplateVersion | Templates |
| 26 | GET | `/ccn/templates/{id}/versions/{version_id}` | getTemplateVersion | Templates |
| 27 | POST | `/ccn/templates/{id}/versions/{version_id}/restore` | restoreTemplateVersion | Templates |
| 28 | POST | `/ccn/templates/{id}/detect_fields` | detectTemplateFields | Templates |
| 29 | PUT | `/templates/{id}` | updateTemplate (fork extension: `preferences`) | Templates |

Path parameters `{id}`, `{version_id}` are integers; `{uuid}` a string; `{key}` a string from the settings
allow-list. Every operation: `security: [{ "AuthToken": [] }]`; responses `200` (documented schema) and `422`
(`{ "error": string }`); list operations return `{ data: [...], pagination: { count, next, prev } }` and accept
`limit`, `after`, `before` query parameters.

MCP tools (not OpenAPI; `tools/list` on `/mcp`): `create_template_from_documents`, `update_template_documents`,
`merge_templates`, `create_submission_from_documents`, `manage_users`, `manage_webhooks`, `account_config`,
`set_template_preferences` — argument schemas in data-model.md.

## Already available upstream (documented in the cheat sheet, no fork operation)

- Unarchive a submission: `PUT /api/submissions/{id}` `{ "archived": false }`.
- Unarchive a template: `PUT /api/templates/{id}` `{ "archived": false }`.
- Resend an invitation: `PUT /api/submitters/{id}` `{ "send_email": true }`.
- Move a template into a folder: `PUT /api/templates/{id}` `{ "folder_name": "Parent / Child" }`.
