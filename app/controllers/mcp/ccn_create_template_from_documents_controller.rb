# frozen_string_literal: true

module Mcp
  # CCN fork — MCP twin of POST /api/templates/{pdf,docx,html} (specs/002-everything-by-api, FR-009).
  class CcnCreateTemplateFromDocumentsController < CcnToolController
    SCHEMA = {
      name: 'create_template_from_documents',
      title: 'Create Template From Documents',
      description: 'Create a template from documents given as base64, data URI or https URL (PDF, images, DOCX and ' \
                   'other office files converted on the server) or from HTML. Text tags such as ' \
                   '{{Name;role=Signer;type=signature}} become fields. With external_id, an existing template ' \
                   'with that id receives the new documents instead of a duplicate. Same behaviour as ' \
                   'POST /api/templates/pdf, /docx and /html.',
      inputSchema: {
        type: 'object',
        properties: {
          format: { type: 'string', enum: %w[pdf docx html],
                    description: "'pdf' (default, also images and office files by content type), 'docx' or 'html'" },
          name: { type: 'string', description: 'Template name (default: the first document name)' },
          folder_name: { type: 'string', description: 'Folder, "Parent / Child" for two levels' },
          external_id: { type: 'string', description: 'Upsert key' },
          documents: {
            type: 'array',
            description: 'Documents in order',
            items: {
              type: 'object',
              properties: {
                file: { type: 'string', description: 'base64, data URI or https URL of the document' },
                html: { type: 'string', description: 'HTML body (format html)' },
                name: { type: 'string' },
                position: { type: 'integer', description: '0-based position in the template' },
                fields: {
                  type: 'array',
                  description: 'Explicit fields: name, type, role, areas [{x, y, w, h, page (from 1)}]',
                  items: { type: 'object' }
                }
              }
            }
          },
          html: { type: 'string', description: 'HTML body when not given per document (format html)' },
          size: { type: 'string', description: 'Page size for HTML: A4, Letter, ...' },
          remove_tags: { type: 'boolean', description: 'Erase the text tags from the pages (default true)' },
          flatten: { type: 'boolean', description: 'Bake PDF form widgets into the pages after detecting them' }
        }
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true }
    }.freeze

    def call
      authorize!(:create, Template)

      format = tool_params[:format].presence || 'pdf'
      documents = Array.wrap(tool_params[:documents])

      files =
        if format == 'html'
          Ccn::HtmlDocuments.files_from(tool_params)
        else
          raise Ccn::DocumentParams::Invalid, 'documents[] is required' if documents.empty?

          Ccn::DocumentParams.files_from(documents)
        end

      template = Ccn::CreateTemplateFromDocuments.call(user: current_user, params: tool_params, files:,
                                                       documents: format == 'html' ? [] : documents)

      render_tool_result(template_summary(template))
    end
  end
end
