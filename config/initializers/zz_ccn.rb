# frozen_string_literal: true

# CCN fork settings (https://github.com/lucouto/docuseal-ccn). Fork locale files are wired in config/application.rb.
module Ccn
  # Where the Corresponding Source of this instance lives (AGPL-3.0 §13). Linked from the signing page
  # attribution and from the version badge in Settings.
  SOURCE_URL = ENV.fetch('CCN_SOURCE_URL', 'https://github.com/lucouto/docuseal-ccn')

  # Settings entries hidden until the corresponding feature is implemented in the fork (FORK-PLAN.md P2).
  SSO_ENABLED = ENV['CCN_SSO_ENABLED'] == 'true'
  SMS_ENABLED = ENV['CCN_SMS_ENABLED'] == 'true'
  # Embedding docs/snippets point at DocuSeal's cloud console and the embed script is a stub here (P2).
  EMBEDDING_ENABLED = ENV['CCN_EMBEDDING_ENABLED'] == 'true'
end
