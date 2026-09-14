# frozen_string_literal: true

module Api
  # CCN fork — /api/ccn/webhooks (specs/002-everything-by-api, US2). Thin over Ccn::ManageWebhooks; secrets
  # only leave through `secret`.
  class CcnWebhooksController < ApiBaseController
    include Ccn::AdminErrors

    before_action { authorize!(:manage, WebhookUrl) }
    before_action :load_webhook, except: %i[index create]

    def index
      webhooks = paginate(Ccn::ManageWebhooks.list(current_account))

      render json: {
        data: webhooks.map { |webhook| Ccn::ManageWebhooks.serialize(webhook) },
        pagination: { count: webhooks.size, next: webhooks.last&.id, prev: webhooks.first&.id }
      }
    end

    def show
      render json: Ccn::ManageWebhooks.serialize(@webhook)
    end

    def create
      render json: Ccn::ManageWebhooks.create(current_account, webhook_attrs)
    end

    def update
      render json: Ccn::ManageWebhooks.update(@webhook, webhook_attrs)
    end

    def destroy
      render json: Ccn::ManageWebhooks.destroy(@webhook)
    end

    def secret
      render json: Ccn::ManageWebhooks.reveal(@webhook)
    end

    def events
      events = paginate(Ccn::ManageWebhooks.events(@webhook, status: params[:status]).preload(:webhook_attempts))

      render json: {
        data: events.map { |event| Ccn::ManageWebhooks.serialize_event(event) },
        pagination: { count: events.size, next: events.last&.id, prev: events.first&.id }
      }
    end

    def resend
      render json: Ccn::ManageWebhooks.resend(@webhook, params[:uuid])
    end

    def test
      render json: Ccn::ManageWebhooks.test(@webhook, current_account)
    end

    private

    def load_webhook
      @webhook = current_account.webhook_urls.find(params[:id])

      authorize!(:manage, @webhook)
    end

    # Attributes at the top level (the API's style) or wrapped in `webhook_url` (the UI's form style).
    def webhook_attrs
      (params[:webhook_url].presence || params).to_unsafe_h
    end
  end
end
