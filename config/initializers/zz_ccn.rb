# frozen_string_literal: true

# CCN fork settings (https://github.com/lucouto/docuseal-ccn). Loaded last (zz_) so it can extend upstream config.
module Ccn
  # Where the Corresponding Source of this instance lives (AGPL-3.0 §13). Linked from the signing page
  # attribution and from the version badge in Settings.
  SOURCE_URL = ENV.fetch('CCN_SOURCE_URL', 'https://github.com/lucouto/docuseal-ccn')

  # Builder field tiles. Upstream's default list minus the types that need a paid service we do not run
  # (phone/SMS verification, payments, identity verification, KBA); adding them back is a one-line change.
  BUILDER_FIELD_TYPES = %w[text signature initials date number image checkbox multiple file radio select cells
                           stamp].freeze

  # Settings entries hidden until the corresponding feature is implemented in the fork (FORK-PLAN.md P2).
  SSO_ENABLED = ENV['CCN_SSO_ENABLED'] == 'true'
  SMS_ENABLED = ENV['CCN_SMS_ENABLED'] == 'true'
end

# Fork strings, loaded after upstream's config/locales/i18n.yml so they can add or override keys.
I18n.load_path += Rails.root.glob('config/locales/ccn/**/*.yml')
