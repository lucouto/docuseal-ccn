# frozen_string_literal: true

module Mcp
  # CCN fork — MCP twin of /api/ccn/webhooks (specs/002-everything-by-api, FR-009), one tool with an `action`.
  class CcnManageWebhooksController < CcnToolController
    ACTIONS = %w[list get create update delete reveal events resend test].freeze
    LIST_LIMIT = 100

    SCHEMA = {
      name: 'manage_webhooks',
      title: 'Manage Webhooks',
      description: 'List, create, update or delete the account\'s webhooks, read their delivery log, resend a ' \
                   'delivery, queue a test delivery, or reveal a webhook\'s secrets (same as /api/ccn/webhooks).',
      inputSchema: {
        type: 'object',
        properties: {
          action: { type: 'string', enum: ACTIONS },
          id: { type: 'integer', description: 'Webhook id (all actions but list and create)' },
          url: { type: 'string', description: 'http(s) URL to call' },
          events: { type: 'array', items: { type: 'string', enum: WebhookUrl::EVENTS },
                    description: 'Events to deliver (default: the four form.* events)' },
          secret: { type: 'object', properties: { key: { type: 'string' }, value: { type: 'string' } },
                    description: 'Custom header sent with each delivery; {} clears it' },
          status: { type: 'string', enum: Ccn::ManageWebhooks::STATUSES, description: 'events: filter' },
          event_uuid: { type: 'string', description: 'resend: the delivery to queue again' }
        },
        required: %w[action]
      },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true }
    }.freeze

    def call
      authorize!(:manage, WebhookUrl)

      account = current_user.account

      case tool_params[:action]
      when 'list'
        webhooks = Ccn::ManageWebhooks.list(account).order(id: :desc).limit(LIST_LIMIT)

        render_tool_result(webhooks.map { |webhook| Ccn::ManageWebhooks.serialize(webhook) })
      when 'create' then render_tool_result(Ccn::ManageWebhooks.create(account, tool_params))
      when 'get' then render_tool_result(Ccn::ManageWebhooks.serialize(webhook))
      when 'update' then render_tool_result(Ccn::ManageWebhooks.update(webhook, tool_params))
      when 'delete' then render_tool_result(Ccn::ManageWebhooks.destroy(webhook))
      when 'reveal' then render_tool_result(Ccn::ManageWebhooks.reveal(webhook))
      when 'events' then render_tool_result(events)
      when 'resend' then render_tool_result(Ccn::ManageWebhooks.resend(webhook, tool_params[:event_uuid]))
      when 'test' then render_tool_result(Ccn::ManageWebhooks.test(webhook, account))
      else raise Ccn::AdminInvalid, "action must be one of #{ACTIONS.join(', ')}"
      end
    end

    private

    def webhook
      raise Ccn::AdminInvalid, 'id is required' if tool_params[:id].blank?

      current_user.account.webhook_urls.find(tool_params[:id])
    end

    def events
      Ccn::ManageWebhooks.events(webhook, status: tool_params[:status])
                         .preload(:webhook_attempts).order(id: :desc).limit(LIST_LIMIT)
                         .map { |event| Ccn::ManageWebhooks.serialize_event(event) }
    end
  end
end
