# CCN fork — change register

Fork of [docusealco/docuseal](https://github.com/docusealco/docuseal) (AGPL-3.0 + `LICENSE_ADDITIONAL_TERMS`) maintained by the Communauté du Chemin Neuf for
https://docuseal.cheminneuf.community. Plan and rationale: `FORK-PLAN.md` in the private ops folder (`~/Projets_apps_github/DocuSeal`).

Branches: `master` mirrors upstream tags untouched · `ccn` = this patch stack, rebased onto each upstream tag.
Release tags: `<upstream>-ccn.<n>` (e.g. `3.2.4-ccn.0`) → image `ghcr.io/lucouto/docuseal-ccn:<tag>`.

## Rules (see FORK-PLAN.md §6)

1. New files first; fill upstream's empty hook partials second; edit upstream files last and minimally.
2. One feature = one commit (or a short series). Every upstream file touched is listed below — this table is the rebase checklist.
3. Migrations additive only: the stock `docuseal/docuseal:<upstream>` image must still boot on our schema.
4. Never modify signing / result generation / audit-trail code.
5. Keep DocuSeal attribution in the UI (AGPL §7(b) additional term) and keep this repository public (AGPL §13).

## Rebase procedure

```
git fetch upstream --tags
git rebase --onto <new-tag> <old-tag> ccn        # resolve using the table below
# CI green → tag <new-tag>-ccn.1 → image builds → staging from prod snapshot → promote
```

## Upstream files touched on `ccn`

| Upstream file | Feature / commit | Why |
|---------------|------------------|-----|
| — | — | none yet (Stage 0 adds only new files) |

## New files owned by the fork

| File | Purpose |
|------|---------|
| `.github/workflows/ccn-image.yml` | GHCR image build on `*-ccn.*` tags (linux/amd64) |
| `CCN-CHANGES.md` | this register |
| `spec/contract/openapi_contract_spec.rb` | contract test: every operation of `docs/openapi.json` implemented here is routable and its responses match the spec |
