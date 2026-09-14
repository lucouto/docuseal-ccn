# frozen_string_literal: true

module Mcp
  # CCN fork — MCP twin of PUT /api/templates/{id}/documents (specs/002-everything-by-api, FR-009).
  class CcnUpdateTemplateDocumentsController < CcnToolController
    SCHEMA = {
      name: 'update_template_documents',
      title: 'Update Template Documents',
      description: 'Add, replace or remove the documents of a template, optionally merging all of them into one ' \
                   'PDF. Same behaviour as PUT /api/templates/{id}/documents.',
      inputSchema: {
        type: 'object',
        properties: {
          template_id: { type: 'integer' },
          documents: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                file: { type: 'string', description: 'base64, data URI or https URL' },
                html: { type: 'string' },
                name: { type: 'string' },
                position: { type: 'integer', description: '0-based position to insert at, replace or remove' },
                replace: { type: 'boolean', description: 'Replace the document at position (fields move over)' },
                remove: { type: 'boolean', description: 'Remove the document at position (fields dropped)' }
              }
            }
          },
          merge: { type: 'boolean', description: 'Merge every document into one PDF afterwards' }
        },
        required: %w[template_id]
      },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true }
    }.freeze

    def call
      template = find_template(tool_params[:template_id])

      authorize!(:update, template)

      template = Ccn::UpdateTemplateDocuments.call(template:, params: tool_params)

      render_tool_result(template_summary(template))
    end
  end
end
