# frozen_string_literal: true

module Mcp
  # CCN fork — MCP twin of /api/ccn/users (specs/002-everything-by-api, FR-009), one tool with an `action`.
  class CcnManageUsersController < CcnToolController
    ACTIONS = %w[list invite update archive reset_password].freeze
    LIST_LIMIT = 100

    SCHEMA = {
      name: 'manage_users',
      title: 'Manage Users',
      description: 'List, invite, update, archive the account\'s users or send them a password reset, with the ' \
                   'same rules as Settings → Users (same as /api/ccn/users).',
      inputSchema: {
        type: 'object',
        properties: {
          action: { type: 'string', enum: ACTIONS },
          id: { type: 'integer', description: 'User id (update, archive, reset_password)' },
          status: { type: 'string', enum: Ccn::ManageUsers::STATUSES, description: 'List filter (default active)' },
          email: { type: 'string' },
          first_name: { type: 'string' },
          last_name: { type: 'string' },
          role: { type: 'string', description: "One of #{User::ROLES.join(', ')}" },
          otp_required_for_login: { type: 'boolean' },
          archived: { type: 'boolean', description: 'update: true archives, false reactivates' },
          send_email: { type: 'boolean', description: 'invite: send the invitation e-mail (default true)' }
        },
        required: %w[action]
      },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false }
    }.freeze

    def call
      authorize!(:manage, User)

      account = current_user.account

      case tool_params[:action]
      when 'list'
        users = Ccn::ManageUsers.list(account, status: tool_params[:status]).order(id: :desc).limit(LIST_LIMIT)

        render_tool_result(users.map { |user| Ccn::ManageUsers.serialize(user) })
      when 'invite'
        render_tool_result(Ccn::ManageUsers.invite(account, current_user, tool_params, send_email: send_email?))
      when 'update' then render_tool_result(Ccn::ManageUsers.update(user, current_user, tool_params))
      when 'archive' then render_tool_result(Ccn::ManageUsers.archive(user, current_user))
      when 'reset_password' then render_tool_result(Ccn::ManageUsers.send_reset_password(user))
      else raise Ccn::AdminInvalid, "action must be one of #{ACTIONS.join(', ')}"
      end
    end

    private

    def user
      raise Ccn::AdminInvalid, 'id is required' if tool_params[:id].blank?

      current_user.account.users.find(tool_params[:id])
    end
  end
end
