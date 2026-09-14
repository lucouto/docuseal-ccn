# frozen_string_literal: true

module Ccn
  # `preferences{}` on PUT /api/templates/{id} and the set_template_preferences MCP tool
  # (specs/002-everything-by-api, US4, FR-004, research D6): the allow-list and coercions of the UI's
  # TemplatesPreferencesController; `null` removes a key; an unknown key is refused.
  module TemplatePreferences
    SCALAR_KEYS = %w[bcc_completed request_email_subject request_email_body invitation_view_email_subject
                     invitation_view_email_body invitation_reminder_email_subject invitation_reminder_email_body
                     documents_copy_email_subject documents_copy_email_body documents_copy_email_enabled
                     documents_copy_email_attach_audit documents_copy_email_attach_documents
                     documents_copy_email_reply_to completed_notification_email_attach_documents
                     completed_redirect_url validate_unique_submitters require_all_submitters submitters_order
                     require_phone_2fa require_email_2fa default_expire_at_duration shared_link_2fa
                     default_expire_at request_email_enabled completed_notification_email_subject
                     completed_notification_email_body completed_notification_email_enabled
                     completed_notification_email_attach_audit].freeze
    NESTED_KEYS = {
      'completed_message' => %w[title body],
      'submitters' => %w[uuid request_email_subject request_email_body],
      'link_form_fields' => nil
    }.freeze
    KEYS = (SCALAR_KEYS + NESTED_KEYS.keys).freeze

    # The two lines the upstream Api::TemplatesController gains (registered in CCN-CHANGES.md): `include` and
    # a call to `ccn_apply_preferences!` before `@template.update!`.
    module ApiHook
      extend ActiveSupport::Concern

      included do
        rescue_from Ccn::AdminInvalid do |e|
          render json: { error: e.message }, status: :unprocessable_content
        end
      end

      private

      def ccn_apply_preferences!
        preferences = params[:preferences] || params.dig(:template, :preferences)

        return if preferences.nil?

        Ccn::TemplatePreferences.apply!(@template, preferences, current_account)
      end
    end

    module_function

    # Merges into template.preferences (not saved): coerced values in, `null` and blank strings/hashes out.
    def apply!(template, preferences, account)
      preferences = to_hash('preferences', preferences)
      unknown = preferences.keys - KEYS

      raise AdminInvalid, I18n.t('ccn_unknown_preference', key: unknown.first) if unknown.any?

      result = template.preferences.to_h.dup

      preferences.each do |key, value|
        value = coerce(key, value, account)

        if value.nil? || ((value.is_a?(String) || value.is_a?(Hash)) && value.blank?)
          result.delete(key)
        else
          result[key] = value
        end
      end

      template.preferences = result

      template
    end

    def coerce(key, value, account)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      return nil if value.nil?

      case key
      when 'default_expire_at' then parse_time(key, value, account)
      when 'completed_message' then nested_hash(key, value, NESTED_KEYS[key])
      when 'submitters' then nested_list(key, value)
      when 'link_form_fields' then string_list(key, value)
      else scalar(key, value)
      end
    end

    def scalar(key, value)
      return value == 'true' if %w[true false].include?(value)
      return value if value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false

      raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: 'string or boolean')
    end

    # As the UI: interpreted in the account's timezone, stored in UTC.
    def parse_time(key, value, account)
      return value if value == ''
      raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: 'datetime') unless value.is_a?(String)

      time = (ActiveSupport::TimeZone[account.timezone.to_s] || Time.zone).parse(value)

      raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: 'datetime') if time.nil?

      time.utc
    rescue ArgumentError
      raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: 'datetime')
    end

    def nested_hash(key, value, members)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      unless value.is_a?(Hash)
        raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: "object with #{members.join(', ')}")
      end

      value = value.to_h.transform_keys(&:to_s)
      unknown = value.keys - members

      if unknown.any?
        raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: "object with #{members.join(', ')}")
      end

      value.transform_values(&:to_s).compact_blank
    end

    def nested_list(key, value)
      raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: 'list') unless value.is_a?(Array)

      value.map { |item| nested_hash(key, item, NESTED_KEYS[key]) }.compact_blank
    end

    def string_list(key, value)
      raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: 'list') unless value.is_a?(Array)

      value.map(&:to_s).compact_blank
    end

    def to_hash(key, value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      raise AdminInvalid, I18n.t('ccn_invalid_preference_value', key:, type: 'object') unless value.is_a?(Hash)

      value.to_h.transform_keys(&:to_s)
    end
  end
end
