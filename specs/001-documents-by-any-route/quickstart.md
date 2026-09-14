# Quickstart: exercising Stage 2 on staging

Staging: `https://docuseal-staging.cheminneuf.community` (fork image, Gotenberg sidecar, no e-mail). Token: `$DOCUSEAL_API_TOKEN` (same as prod). CLI: `docuseal … --server https://docuseal-staging.cheminneuf.community`.

```bash
S=https://docuseal-staging.cheminneuf.community
# 1. Text tags in a PDF → template with 8 fields, tags erased
docuseal templates create-pdf --server $S --name "Tags demo" --file ~/Projets_apps_github/DocuSeal/fieldtags-upstream-example.pdf
# 2. Same from the Word original (converted by the sidecar)
docuseal templates create-docx --server $S --name "Tags demo (docx)" --file ~/Projets_apps_github/docuseal-ccn/spec/fixtures/fieldtags.docx
# 3. HTML with field elements, A4
docuseal templates create-html --server $S --name "HTML demo" --size A4 \
  --html '<h1>Lease</h1><p>Tenant: <text-field name="Tenant" role="Tenant" style="width:200px;height:24px"></text-field></p><signature-field name="Sign" role="Tenant" style="width:220px;height:60px"></signature-field>'
# 4. Merge two templates, rename roles
docuseal templates merge --server $S --name "Merged" -d 'template_ids[]=ID1' -d 'template_ids[]=ID2' -d 'roles[]=Tenant' -d 'roles[]=Landlord'
# 5. Add a document to a template, then merge all its documents into one PDF
docuseal templates update-documents --server $S ID -d "documents[0][file]=$(base64 < extra.pdf)" -d 'documents[0][name]=Annex'
docuseal templates update-documents --server $S ID --merge
# 6. One-shot signature request (no e-mail on staging)
docuseal submissions create-pdf --server $S --file lease.pdf --no-send-email -d 'submitters[0][email]=tenant@example.com' -d 'submitters[0][role]=Tenant'
# Gate: ./staging-s2-check.sh in ~/Projets_apps_github/DocuSeal runs 1–6 with fixtures and asserts the 8 fields, erased tags, 200s and a completable signing link.
```

Raw HTTP equivalent of 1:

```bash
curl -s -X POST "$S/api/templates/pdf" -H "X-Auth-Token: $DOCUSEAL_API_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"name\":\"Tags demo\",\"documents\":[{\"name\":\"tags\",\"file\":\"$(base64 < fieldtags.pdf)\"}]}" | jq '.fields | length'   # → 8
```
