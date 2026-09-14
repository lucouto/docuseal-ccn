# Quickstart: reminders, account logo, editor/viewer roles

Base URL `$BASE` (`https://docuseal-staging.cheminneuf.community/api`), header `X-Auth-Token: $DOCUSEAL_API_TOKEN`.
These steps are what `staging-s4-check.sh` runs and reverts (temporary users archived, config restored, logo
removed).

```bash
H=(-H "X-Auth-Token: $DOCUSEAL_API_TOKEN" -H 'Content-Type: application/json')

# Reminders — set short durations, create a submission, move sent_at back, run
curl -s "${H[@]}" -X PUT "$BASE/ccn/account_configs/submitter_reminders" \
  -d '{"value":{"first_duration":"one_hour","second_duration":"two_hours","third_duration":"four_hours"}}'
curl -s "${H[@]}" -X POST "$BASE/submissions/pdf" -d @/tmp/s4-submission.json   # send_email:true, one submitter
# sent_at moved back 2h via `rails runner` over ssh (gate script only — never by hand in prod)
curl -s "${H[@]}" "$BASE/ccn/reminders/due" | jq '.data[] | {email, stage}'
curl -s "${H[@]}" -X POST "$BASE/ccn/reminders/run" -d '{"dry_run":true}'
curl -s "${H[@]}" -X POST "$BASE/ccn/reminders/run" -d '{}'                    # staging has no SMTP: reports "skipped", writes no event
curl -s "${H[@]}" -X DELETE "$BASE/ccn/account_configs/submitter_reminders"    # restore

# Account logo
curl -s "${H[@]}" -X PUT "$BASE/ccn/account_logo" -d '{"file":"data:image/png;base64,'"$(base64 < logo.png)"'"}'
curl -s "${H[@]}" "$BASE/ccn/account_logo" | jq .url
curl -s "https://docuseal-staging.cheminneuf.community/s/$SLUG" | grep -o '<img[^>]*logo[^>]*>'
curl -s "https://docuseal-staging.cheminneuf.community/s/$SLUG" | grep -o 'Powered by DocuSeal[^<]*'
curl -s "${H[@]}" -X DELETE "$BASE/ccn/account_logo"                           # restore the DocuSeal mark

# Roles — invite an editor and a viewer, run the 200/403 matrix, archive both
EID=$(curl -s "${H[@]}" -X POST "$BASE/ccn/users" -d '{"email":"s4-editor@example.com","role":"editor","send_email":false}' | jq -r .id)
VID=$(curl -s "${H[@]}" -X POST "$BASE/ccn/users" -d '{"email":"s4-viewer@example.com","role":"viewer","send_email":false}' | jq -r .id)
# API tokens for EID/VID minted via `rails runner` over ssh, read into shell variables, never printed
curl -s -H "X-Auth-Token: $EDITOR_TOKEN" "$BASE/templates" -o /dev/null -w '%{http_code}\n'          # 200
curl -s -H "X-Auth-Token: $EDITOR_TOKEN" "$BASE/ccn/users" -o /dev/null -w '%{http_code}\n'            # 403
curl -s -H "X-Auth-Token: $VIEWER_TOKEN" "$BASE/templates" -o /dev/null -w '%{http_code}\n'          # 200
curl -s -H "X-Auth-Token: $VIEWER_TOKEN" -X POST "$BASE/submissions" -d '{}' -o /dev/null -w '%{http_code}\n'  # 403
curl -s "${H[@]}" -X DELETE "$BASE/ccn/users/$EID"
curl -s "${H[@]}" -X DELETE "$BASE/ccn/users/$VID"

# Last-admin guard (on the sole admin account used for the gate, expect 422 — do not actually leave the account admin-less)
curl -s "${H[@]}" -X PUT "$BASE/ccn/users/$SELF_ID" -d '{"role":"editor"}' -o /dev/null -w '%{http_code}\n'  # 422
```
