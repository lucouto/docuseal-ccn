# frozen_string_literal: true

class McpController < ActionController::Metal
  TOOL_CONTROLLERS = {
    'search_templates' => Mcp::SearchTemplatesController,
    'load_template' => Mcp::LoadTemplateController,
    'create_template' => Mcp::CreateTemplateController,
    'send_documents' => Mcp::SendDocumentsController,
    'search_documents' => Mcp::SearchDocumentsController,
    # CCN fork (specs/002-everything-by-api, FR-009): the fork's API as tools, same services as REST.
    'create_template_from_documents' => Mcp::CcnCreateTemplateFromDocumentsController,
    'update_template_documents' => Mcp::CcnUpdateTemplateDocumentsController,
    'merge_templates' => Mcp::CcnMergeTemplatesController,
    'create_submission_from_documents' => Mcp::CcnCreateSubmissionFromDocumentsController,
    'manage_users' => Mcp::CcnManageUsersController,
    'manage_webhooks' => Mcp::CcnManageWebhooksController,
    'account_config' => Mcp::CcnAccountConfigController,
    'set_template_preferences' => Mcp::CcnSetTemplatePreferencesController
  }.freeze

  TOOLS = TOOL_CONTROLLERS.map { |_, controller| controller::SCHEMA }.freeze

  def call
    return Mcp::ProtocolController.dispatch(:ok, request, response) if request.raw_post.blank?

    body = JSON.parse(request.raw_post)
    body = nil unless body.is_a?(Hash)

    request.request_parameters = body || {}

    action =
      case body&.dig('method')
      when 'initialize' then :initialize_request
      when 'notifications/initialized' then :initialized_notification
      when 'ping' then :ping
      when 'tools/list' then :tools_list
      when 'tools/call'
        tool = TOOL_CONTROLLERS[body.dig('params', 'name')]

        return tool.dispatch(:call, request, response) if tool

        :tool_not_found
      else
        :method_not_found
      end

    Mcp::ProtocolController.dispatch(action, request, response)
  rescue JSON::ParserError
    request.request_parameters = {}

    Mcp::ProtocolController.dispatch(:parse_error, request, response)
  end
end
