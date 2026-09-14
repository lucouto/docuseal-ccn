# frozen_string_literal: true

# CCN fork namespace (register of changes: CCN-CHANGES.md). Configuration is read once from the environment
# when the file loads; plain Ruby only, so the constants are usable from initializers' to_prepare blocks
# and from the standalone formula smoke harness.
module Ccn
  SOURCE_URL = ENV.fetch('CCN_SOURCE_URL', 'https://github.com/lucouto/docuseal-ccn')
  SSO_ENABLED = ENV['CCN_SSO_ENABLED'] == 'true'
  SMS_ENABLED = ENV['CCN_SMS_ENABLED'] == 'true'
  EMBEDDING_ENABLED = ENV['CCN_EMBEDDING_ENABLED'] == 'true'

  # Conversion sidecar (Gotenberg, FORK-PLAN.md §5.2). Nil → DOCX/HTML ingestion answers HTTP 422.
  gotenberg_url = ENV['GOTENBERG_URL'].to_s.strip.chomp('/')
  GOTENBERG_URL = gotenberg_url.empty? ? nil : gotenberg_url

  # Paper sizes accepted by the HTML ingestion endpoints, in inches (Gotenberg paperWidth / paperHeight).
  PAGE_SIZES = {
    'Letter' => [8.5, 11], 'Legal' => [8.5, 14], 'Tabloid' => [11, 17], 'Ledger' => [17, 11],
    'A0' => [33.1, 46.8], 'A1' => [23.4, 33.1], 'A2' => [16.5, 23.4], 'A3' => [11.7, 16.5],
    'A4' => [8.27, 11.69], 'A5' => [5.83, 8.27], 'A6' => [4.13, 5.83]
  }.freeze

  # The published API default is Letter; this instance may override it (CCN: A4) — FORK-PLAN.md §9.7.
  DEFAULT_PAGE_SIZE = PAGE_SIZES.key?(ENV['CCN_DEFAULT_PAGE_SIZE'].to_s) ? ENV['CCN_DEFAULT_PAGE_SIZE'] : 'Letter'

  # Documented HTTP 422 for options the fork does not implement yet (dynamic DOCX, variables, template_ids).
  NotSupportedYet = Class.new(StandardError)
end
