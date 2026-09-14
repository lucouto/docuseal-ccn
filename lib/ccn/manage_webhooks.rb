# frozen_string_literal: true

module Ccn
  # /api/ccn/webhooks and the manage_webhooks MCP tool (specs/002-everything-by-api, US2, FR-002): the rules
  # of the UI's WebhookSettings / WebhookPreferences / WebhookSecret / WebhookEvents controllers. Secrets are
  # write-only except through `reveal` (research D5).
  module ManageWebhooks
    DEFAULT_EVENTS = %w[form.viewed form.started form.completed form.declined].freeze
    SERIALIZE_ONLY = %i[id url events created_at updated_at].freeze
    EVENT_SERIALIZE_ONLY = %i[uuid event_type record_type record_id status created_at].freeze
    ATTEMPT_SERIALIZE_ONLY = %i[attempt response_status_code created_at].freeze
    STATUSES = %w[success error].freeze

    module_function

    # @return [ActiveRecord::Relation] unordered; the controller paginates
    def list(account)
      account.webhook_urls
    end

    def create(account, attrs)
      attrs = permitted(attrs)
      webhook = account.webhook_urls.new(url: attrs['url'].to_s.strip)
      webhook.events = attrs.fetch('events') { DEFAULT_EVENTS.dup }
      webhook.secret = attrs['secret'] if attrs.key?('secret')

      save!(webhook)
    end

    def update(webhook, attrs)
      attrs = permitted(attrs)
      webhook.url = attrs['url'].to_s.strip if attrs.key?('url')
      webhook.events = attrs['events'] if attrs.key?('events')
      webhook.secret = attrs['secret'] if attrs.key?('secret')

      save!(webhook)
    end

    def destroy(webhook)
      webhook.destroy!

      { 'id' => webhook.id, 'deleted' => true }
    end

    def serialize(webhook)
      webhook.as_json(only: SERIALIZE_ONLY).merge('secret_key' => webhook.secret.to_h.keys.first)
    end

    # The one place the custom header and the HMAC signing secret are readable (WebhookSecretController#show).
    def reveal(webhook)
      { 'secret' => webhook.secret.to_h, 'hmac_secret' => webhook.hmac_secret }
    end

    # @return [ActiveRecord::Relation] deliveries, unordered; the controller paginates
    def events(webhook, status: nil)
      events = webhook.webhook_events

      case status.to_s
      when '' then events
      when *STATUSES then events.where(status: status.to_s)
      else raise AdminInvalid, I18n.t('ccn_unknown_status', status:, statuses: STATUSES.join(', '))
      end
    end

    def serialize_event(event)
      attempts = event.webhook_attempts.sort_by(&:id).map { |attempt| attempt.as_json(only: ATTEMPT_SERIALIZE_ONLY) }

      event.as_json(only: EVENT_SERIALIZE_ONLY).merge('attempts' => attempts)
    end

    # Same job and arguments as WebhookEventsController#resend.
    def resend(webhook, uuid)
      event = webhook.webhook_events.find_by!(uuid:)
      id_key = WebhookUrls::EVENT_TYPE_ID_KEYS.fetch(event.event_type.split('.').first)

      WebhookUrls::EVENT_TYPE_TO_JOB_CLASS.fetch(event.event_type).perform_async(
        id_key => event.record_id,
        'webhook_url_id' => webhook.id,
        'event_uuid' => event.uuid,
        'attempt' => SendWebhookRequest::MANUAL_ATTEMPT,
        'last_status' => 0
      )

      { 'queued' => true, 'event_uuid' => event.uuid }
    end

    # Same job as WebhookSettingsController#resend: a form.completed payload built from the account's last
    # completed submitter.
    def test(webhook, account)
      submitter = account.submitters.where.not(completed_at: nil).order(:id).last

      raise AdminInvalid, I18n.t('ccn_no_completed_submitter') if submitter.blank?

      event_uuid = SecureRandom.uuid

      SendTestWebhookRequestJob.perform_async('submitter_id' => submitter.id, 'event_uuid' => event_uuid,
                                              'webhook_url_id' => webhook.id)

      { 'queued' => true, 'event_uuid' => event_uuid }
    end

    def permitted(attrs)
      attrs = Ccn::DocumentParams.indifferent(attrs).slice('url', 'events', 'secret').to_h

      attrs['events'] = validated_events(attrs['events']) if attrs.key?('events')
      attrs['secret'] = normalize_secret(attrs['secret']) if attrs.key?('secret')

      attrs
    end

    def validated_events(events)
      events = Array.wrap(events).map(&:to_s).uniq
      unknown = events - WebhookUrl::EVENTS

      if unknown.any?
        raise AdminInvalid, I18n.t('ccn_unknown_webhook_event', event: unknown.first,
                                                                events: WebhookUrl::EVENTS.join(', '))
      end

      events
    end

    # `{ key:, value: }` (the UI's form) or `{ "X-Header" => "value" }`; one header; blank clears.
    def normalize_secret(secret)
      secret = secret.to_unsafe_h if secret.respond_to?(:to_unsafe_h)

      raise AdminInvalid, I18n.t('ccn_invalid_webhook_secret') unless secret.nil? || secret.is_a?(Hash)

      secret = secret.to_h.transform_keys(&:to_s)
      secret = { secret['key'].to_s => secret['value'].to_s } if secret.key?('key') || secret.key?('value')

      secret.compact_blank.first(1).to_h
    end

    def save!(webhook)
      validate_url!(webhook.url)
      webhook.save!

      serialize(webhook)
    end

    def validate_url!(url)
      uri = URI.parse(url.to_s)

      raise AdminInvalid, I18n.t('ccn_invalid_webhook_url') unless uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      raise AdminInvalid, I18n.t('ccn_invalid_webhook_url')
    end
  end
end
