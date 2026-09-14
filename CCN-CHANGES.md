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
| `Gemfile`, `Gemfile.lock` | Stage 1 — formulas | adds `dentaku` (MIT): server-side counterpart of the client calculator (a JS port of Dentaku) |
| `lib/submitters/submit_values.rb` | Stage 1 — formulas | replaces the two Pro stubs `calculate_formula_value` (returned 0) and `eval_text_formula_value` (returned '') |
| `app/views/templates/edit.html.erb` | Stage 1 — builder | `data-with-conditions`, `data-with-formula` |
| `app/javascript/template_builder/fields.vue` | Stage 1 — de-Pro | locked "phone" upsell tile (→ docuseal.com/pricing) removed |
| `app/javascript/submission_form/formula_areas.vue` | Stage 1 — formulas | referenced values coerced to numbers (`numericFormulaValue`) with the same rule as the server |
| `config/application.rb` | Stage 1 — i18n | `config.i18n.load_path += config/locales/ccn/**/*.yml` (after upstream's file, so keys can be overridden) |
| `app/views/shared/_settings_nav.html.erb` | Stage 1 — de-Pro | Plans/Console entries multitenant-only; SSO/SMS behind `Ccn::SSO_ENABLED`/`SMS_ENABLED`; version badge → fork release |
| `app/views/shared/_navbar_buttons.html.erb` | Stage 1 — de-Pro | "Upgrade" button on /settings removed |
| `app/views/shared/_navbar.html.erb` | Stage 1 — de-Pro | user-menu "Console" entry (→ console.docuseal.com) multitenant-only |
| `app/views/templates_preferences/show.html.erb`, `app/views/templates_code_modal/show.html.erb` | Stage 1 — de-Pro | `templates/embedding` snippets behind `Ccn::EMBEDDING_ENABLED` (embed script is a stub here; snippets link to the cloud console) |
| `app/views/shared/_powered_by.html.erb` | Stage 1 — AGPL §13 | adds the source-code link next to the DocuSeal attribution (attribution kept, §7(b)) |
| `app/views/users/_role_select.html.erb` | Stage 1 — de-Pro | upsell link removed (roles come with Stage 4) |
| `app/views/sso_settings/_placeholder.html.erb`, `sms_settings/_placeholder.html.erb`, `templates_code_modal/_placeholder.html.erb` | Stage 1 — de-Pro | render `shared/ccn_not_yet` |
| `app/views/submissions/_send_sms_button.html.erb`, `app/views/esign_settings/_default_signature_row.html.erb` | Stage 1 — de-Pro | emptied (SMS is P2; the AATL row is DocuSeal's own certificate) |
| hook partials `personalization_settings/_logo_form`, `notifications_settings/_reminder_banner`, `submissions/_list_form` | Stage 1 — de-Pro | render `shared/ccn_not_yet` until Stage 2/4 fill them |

## New files owned by the fork

| File | Purpose |
|------|---------|
| `.github/workflows/ccn-image.yml` | GHCR image build on `*-ccn.*` tags (linux/amd64) |
| `CCN-CHANGES.md` | this register |
| `config/initializers/zz_ccn.rb` | `Ccn::SOURCE_URL`, `SSO_ENABLED`, `SMS_ENABLED`, `EMBEDDING_ENABLED` |
| `config/locales/ccn/ccn.yml` | fork strings (en, fr) |
| `app/views/shared/_ccn_not_yet.html.erb` | neutral "not available on this instance yet" notice |
| `spec/requests/ccn_stage1_spec.rb` | Stage 1 gate: switches on, no upsell strings on reachable pages, attribution + source link, formulas/conditions on completion |
| `spec/requests/openapi_contract_spec.rb` + `spec/support/openapi_contract.rb` | contract test: every operation of `docs/openapi.json` is routable except the pinned PENDING list, and each implemented operation's real response matches its declared schema (dependency-free validator) |
