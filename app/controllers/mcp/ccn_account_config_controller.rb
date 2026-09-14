# frozen_string_literal: true

module Mcp
  # CCN fork — MCP twin of /api/ccn/account_configs (specs/002-everything-by-api, FR-009).
  class CcnAccountConfigController < CcnToolController
    ACTIONS = %w[list get set reset].freeze

    SCHEMA = {
      name: 'account_config',
      title: 'Account Configuration',
      description: 'Read or change the account settings the UI exposes (signing options, e-mail templates, ' \
                   'reminders, BCC, completion screen). Encrypted settings (SMTP, storage, certificates) are ' \
                   'not reachable. Same as /api/ccn/account_configs.',
      inputSchema: {
        type: 'object',
        properties: {
          action: { type: 'string', enum: ACTIONS },
          key: { type: 'string', enum: Ccn::ManageAccountConfigs::KEYS.keys,
                 description: 'Setting key (get, set, reset)' },
          value: { description: 'set: boolean, string or object depending on the key (list shows each type); ' \
                                'blank resets' }
        },
        required: %w[action]
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }
    }.freeze

    def call
      authorize!(:manage, AccountConfig)

      account = current_user.account

      case tool_params[:action]
      when 'list' then render_tool_result(Ccn::ManageAccountConfigs.list(account))
      when 'get' then render_tool_result(Ccn::ManageAccountConfigs.get(account, key))
      when 'set' then render_tool_result(Ccn::ManageAccountConfigs.set(account, key, mcp_params['value']))
      when 'reset' then render_tool_result(Ccn::ManageAccountConfigs.reset(account, key))
      else raise Ccn::AdminInvalid, "action must be one of #{ACTIONS.join(', ')}"
      end
    end

    private

    def key
      raise Ccn::AdminInvalid, 'key is required' if tool_params[:key].blank?

      tool_params[:key].to_s
    end
  end
end
