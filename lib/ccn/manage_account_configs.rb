# frozen_string_literal: true

module Ccn
  # /api/ccn/account_configs and the account_config MCP tool (specs/002-everything-by-api, US3, FR-003): the
  # union of the keys the three UI settings controllers allow (AccountConfigs, PersonalizationSettings,
  # NotificationsSettings), each with a declared type so a wrong shape is a precise 422 and never stored.
  # EncryptedConfig keys are not in the table: they are "unknown settings" by construction (research D4).
  module ManageAccountConfigs
    TRUE_VALUES = [true, 'true', '1', 1].freeze
    FALSE_VALUES = [false, 'false', '0', 0].freeze
    BOOLEAN = { type: 'boolean' }.freeze
    STRING = { type: 'string' }.freeze
    EMAIL_MEMBERS = %w[subject body reply_to].freeze
    MAX_STRING_BYTES = 20_000

    KEYS = {
      # AccountConfigsController::ALLOWED_KEYS — the toggles of Settings → Account / E-signature
      AccountConfig::ALLOW_TYPED_SIGNATURE => BOOLEAN,
      AccountConfig::FORCE_MFA => BOOLEAN,
      AccountConfig::ALLOW_TO_RESUBMIT => BOOLEAN,
      AccountConfig::ALLOW_TO_DECLINE_KEY => BOOLEAN,
      AccountConfig::ALLOW_TO_DELEGATE_KEY => BOOLEAN,
      AccountConfig::FORM_PREFILL_SIGNATURE_KEY => BOOLEAN,
      AccountConfig::ESIGNING_PREFERENCE_KEY => STRING,
      AccountConfig::FORM_WITH_CONFETTI_KEY => BOOLEAN,
      AccountConfig::DOWNLOAD_LINKS_AUTH_KEY => BOOLEAN,
      AccountConfig::DOWNLOAD_LINKS_EXPIRE_KEY => BOOLEAN,
      AccountConfig::FORCE_SSO_AUTH_KEY => BOOLEAN,
      AccountConfig::FLATTEN_RESULT_PDF_KEY => BOOLEAN,
      AccountConfig::ENFORCE_SIGNING_ORDER_KEY => BOOLEAN,
      AccountConfig::WITH_FILE_LINKS_KEY => BOOLEAN,
      AccountConfig::WITH_SIGNATURE_ID => BOOLEAN,
      AccountConfig::COMBINE_PDF_RESULT_KEY => BOOLEAN,
      AccountConfig::REQUIRE_SIGNING_REASON_KEY => BOOLEAN,
      AccountConfig::DOCUMENT_FILENAME_FORMAT_KEY => STRING,
      AccountConfig::ENABLE_MCP_KEY => BOOLEAN,
      # PersonalizationSettingsController::ALLOWED_KEYS — e-mail templates and completion screen
      AccountConfig::FORM_COMPLETED_BUTTON_KEY => { type: 'object', members: %w[title url] },
      AccountConfig::SUBMITTER_INVITATION_EMAIL_KEY => { type: 'object', members: EMAIL_MEMBERS },
      AccountConfig::SUBMITTER_INVITATION_REMINDER_EMAIL_KEY => { type: 'object', members: EMAIL_MEMBERS },
      AccountConfig::SUBMITTER_DOCUMENTS_COPY_EMAIL_KEY => {
        type: 'object', members: %w[subject body reply_to attach_audit_log attach_documents bcc_recipients enabled]
      },
      AccountConfig::SUBMITTER_COMPLETED_EMAIL_KEY => {
        type: 'object', members: %w[subject body attach_audit_log attach_documents]
      },
      AccountConfig::FORM_COMPLETED_MESSAGE_KEY => { type: 'object', members: %w[title body] },
      AccountConfig::POLICY_LINKS_KEY => STRING,
      # NotificationsSettingsController
      AccountConfig::BCC_EMAILS => STRING,
      AccountConfig::SUBMITTER_REMINDERS => {
        type: 'object', members: %w[first_duration second_duration third_duration],
        values: AccountConfigs::REMINDER_DURATIONS.keys
      }
    }.freeze

    module_function

    def list(account)
      stored = account.account_configs.where(key: KEYS.keys).index_by(&:key)

      KEYS.keys.map { |key| serialize(key, stored[key]) }
    end

    def get(account, key)
      definition!(key)

      serialize(key, account.account_configs.find_by(key:))
    end

    # A blank value behaves like `reset` (the UI destroys the row); `false` is a stored value.
    def set(account, key, value)
      value = coerce(key, definition!(key), value)

      return reset(account, key) if value.nil?

      config = account.account_configs.find_or_initialize_by(key:)
      config.update!(value:)

      serialize(key, config)
    end

    def reset(account, key)
      definition!(key)

      account.account_configs.where(key:).destroy_all

      serialize(key, nil)
    end

    def serialize(key, config)
      data = { 'key' => key, 'type' => KEYS.fetch(key)[:type], 'value' => config&.value }
      default = AccountConfig::DEFAULT_VALUES[key]&.call
      data['default'] = default if default

      data
    end

    def definition!(key)
      KEYS.fetch(key.to_s) { raise AdminInvalid, I18n.t('ccn_unknown_setting', key:) }
    end

    # @return [Object, nil] the value to store, nil when it means "remove"
    def coerce(key, definition, value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      return nil if value.nil? || value == '' || value == {}

      case definition[:type]
      when 'boolean' then coerce_boolean(key, value)
      when 'string' then coerce_string(key, value)
      else coerce_object(key, definition, value)
      end
    end

    def coerce_boolean(key, value)
      return true if TRUE_VALUES.include?(value)
      return false if FALSE_VALUES.include?(value)

      raise AdminInvalid, I18n.t('ccn_invalid_setting_value', key:, type: 'boolean')
    end

    def coerce_string(key, value)
      raise AdminInvalid, I18n.t('ccn_invalid_setting_value', key:, type: 'string') unless value.is_a?(String)
      check_size!(key, value)

      value
    end

    # Members outside the list → 422; 'true'/'false' members become booleans (the UI's coercion); blank
    # members are dropped; nothing left → remove.
    def coerce_object(key, definition, value)
      raise AdminInvalid, I18n.t('ccn_invalid_setting_value', key:, type: 'object') unless value.is_a?(Hash)

      value = value.to_h.transform_keys(&:to_s)
      unknown = value.keys - definition[:members]

      raise AdminInvalid, I18n.t('ccn_invalid_setting_member', key:, member: unknown.first) if unknown.any?

      value = value.transform_values { |member| coerce_member(key, member) }
      value = value.reject { |_, member| member.nil? || member == '' } # `false` is a stored member
      validate_values!(key, definition, value)

      value.presence
    end

    def coerce_member(key, member)
      return true if [true, 'true'].include?(member)
      return false if [false, 'false'].include?(member)
      return member if member.nil?

      return check_size!(key, member.to_s) if member.is_a?(String) || member.is_a?(Numeric)

      raise AdminInvalid, I18n.t('ccn_invalid_setting_value', key:, type: 'object of strings and booleans')
    end

    def check_size!(key, value)
      return value if value.bytesize <= MAX_STRING_BYTES

      raise AdminInvalid, I18n.t('ccn_setting_too_long', key:, max: MAX_STRING_BYTES)
    end

    def validate_values!(key, definition, value)
      return unless definition[:values]

      bad = value.values.find { |member| definition[:values].exclude?(member) }
      return unless bad

      type = "duration (#{definition[:values].join(', ')})"

      raise AdminInvalid, I18n.t('ccn_invalid_setting_value', key:, type:)
    end
  end
end
