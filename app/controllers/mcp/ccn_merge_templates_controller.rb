# frozen_string_literal: true

module Mcp
  # CCN fork — MCP twin of POST /api/templates/merge (specs/002-everything-by-api, FR-009).
  class CcnMergeTemplatesController < CcnToolController
    SCHEMA = {
      name: 'merge_templates',
      title: 'Merge Templates',
      description: 'Create one new template holding the documents and fields of several templates, in order; ' \
                   'the sources are untouched. Same behaviour as POST /api/templates/merge.',
      inputSchema: {
        type: 'object',
        properties: {
          template_ids: { type: 'array', items: { type: 'integer' }, description: 'Templates to merge, in order' },
          name: { type: 'string', description: 'Name of the merged template (default: "<first> (Merged)")' },
          folder_name: { type: 'string' },
          roles: { type: 'array', items: { type: 'string' },
                   description: 'Signer roles of the merged template, matched positionally onto each source' }
        },
        required: %w[template_ids]
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false }
    }.freeze

    def call
      authorize!(:create, Template)

      templates = Ccn::MergeTemplates.find_templates(current_ability, tool_params[:template_ids])
      template = Ccn::MergeTemplates.call(user: current_user, templates:, params: tool_params)

      render_tool_result(template_summary(template))
    end
  end
end
