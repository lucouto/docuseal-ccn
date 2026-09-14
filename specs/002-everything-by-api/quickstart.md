# Quickstart: administering DocuSeal CCN by API

Base URL `$BASE` (`https://docuseal-staging.cheminneuf.community/api`), header `X-Auth-Token: $DOCUSEAL_API_TOKEN`.
These steps are what `staging-s3-check.sh` (operations directory) runs and reverts.

```bash
H=(-H "X-Auth-Token: $DOCUSEAL_API_TOKEN" -H 'Content-Type: application/json')

# Users
curl -s "${H[@]}" "$BASE/ccn/users" | jq '.data[] | {id, email, role}'
curl -s "${H[@]}" -X POST "$BASE/ccn/users" -d '{"email":"s3-gate@example.com","first_name":"S3","last_name":"Gate","send_email":false}'
curl -s "${H[@]}" -X PUT "$BASE/ccn/users/$UID" -d '{"last_name":"Gate II"}'
curl -s "${H[@]}" -X DELETE "$BASE/ccn/users/$UID"                       # archive
curl -s "${H[@]}" "$BASE/ccn/users?status=archived" | jq '.data[].email'

# Webhooks
curl -s "${H[@]}" -X POST "$BASE/ccn/webhooks" -d '{"url":"https://n8n.example/hook","events":["form.completed"],"secret":{"key":"X-Token","value":"s3"}}'
curl -s "${H[@]}" "$BASE/ccn/webhooks/$WID/secret"                       # the only place secrets appear
curl -s "${H[@]}" -X PUT "$BASE/ccn/webhooks/$WID" -d '{"events":["form.completed","submission.completed"]}'
curl -s "${H[@]}" -X POST "$BASE/ccn/webhooks/$WID/test"
curl -s "${H[@]}" "$BASE/ccn/webhooks/$WID/events?status=error"
curl -s "${H[@]}" -X DELETE "$BASE/ccn/webhooks/$WID"

# Account settings
curl -s "${H[@]}" "$BASE/ccn/account_configs" | jq '.data[] | {key, type, value}'
curl -s "${H[@]}" -X PUT "$BASE/ccn/account_configs/allow_typed_signature" -d '{"value":false}'
curl -s "${H[@]}" -X PUT "$BASE/ccn/account_configs/submitter_reminders" -d '{"value":{"first_duration":"twenty_four_hours","second_duration":"three_days"}}'
curl -s "${H[@]}" -X DELETE "$BASE/ccn/account_configs/allow_typed_signature"   # back to default
curl -s "${H[@]}" "$BASE/ccn/account_configs/action_mailer_smtp"                # 422: unknown setting

# Templates: preferences, folders, versions, detection
curl -s "${H[@]}" -X PUT "$BASE/templates/$TID" -d '{"preferences":{"request_email_subject":"Merci de signer {{template.name}}","completed_redirect_url":"https://chemin-neuf.org"}}'
curl -s "${H[@]}" "$BASE/templates/$TID" | jq .preferences
curl -s "${H[@]}" -X PUT "$BASE/templates/$TID" -d '{"preferences":{"completed_redirect_url":null}}'
curl -s "${H[@]}" -X POST "$BASE/ccn/template_folders" -d '{"name":"S3 gate / Sub"}'
curl -s "${H[@]}" -X PUT "$BASE/templates/$TID" -d '{"folder_name":"S3 gate / Sub"}'
curl -s "${H[@]}" -X POST "$BASE/ccn/templates/$TID/versions"
curl -s "${H[@]}" "$BASE/ccn/templates/$TID/versions" | jq '.data[0]'
curl -s "${H[@]}" -X POST "$BASE/ccn/templates/$TID/versions/$VID/restore"
curl -s "${H[@]}" -X POST "$BASE/ccn/templates/$TID/detect_fields" -d '{"apply":false}' | jq '.documents[0].pages[0].fields | length'

# MCP (Bearer MCP token, account with enable_mcp)
curl -s -H "Authorization: Bearer $DOCUSEAL_MCP_TOKEN" -H 'Content-Type: application/json' "$BASE/../mcp" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq '.result.tools[].name'
```
