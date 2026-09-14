# frozen_string_literal: true

module Mcp
  # CCN fork — MCP twin of `preferences` on PUT /api/templates/{id} (specs/002-everything-by-api, FR-009).
  class CcnSetTemplatePreferencesController < CcnToolController
    SCHEMA = {
      name: 'set_template_preferences',
      title: 'Set Template Preferences',
      description: 'Set a template\'s per-template preferences: request/invitation/reminder/documents-copy/' \
                   'completion e-mail subjects and bodies, completed_redirect_url, default_expire_at, 2FA ' \
                   'requirements, submitters_order, bcc_completed, completed_message {title, body}, ' \
                   'link_form_fields. A null value removes a key. Same keys as Settings → Preferences and as ' \
                   'PUT /api/templates/{id}.',
      inputSchema: {
        type: 'object',
        properties: {
          template_id: { type: 'integer' },
          preferences: { type: 'object', description: "Keys among: #{Ccn::TemplatePreferences::KEYS.join(', ')}" }
        },
        required: %w[template_id preferences]
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }
    }.freeze

    def call
      template = find_template(tool_params[:template_id])

      authorize!(:update, template)

      Ccn::TemplatePreferences.apply!(template, mcp_params['preferences'] || {}, current_user.account)
      template.save!

      WebhookUrls.enqueue_events(template, 'template.updated')

      render_tool_result(id: template.id, name: template.name, preferences: template.preferences)
    end
  end
end
