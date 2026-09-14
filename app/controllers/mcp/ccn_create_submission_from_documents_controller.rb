# frozen_string_literal: true

module Mcp
  # CCN fork — MCP twin of POST /api/submissions/{pdf,docx,html} (specs/002-everything-by-api, FR-009): the
  # same transient template → create → detach → discard sequence (Ccn::CreateSubmissionFromDocuments); the
  # submitters are normalised as upstream's own send_documents tool does (e-mail, name, phone, role, prefilled
  # read-only fields).
  class CcnCreateSubmissionFromDocumentsController < CcnToolController
    SCHEMA = {
      name: 'create_submission_from_documents',
      title: 'Create Submission From Documents',
      description: 'Send documents for signing without a saved template: the documents (base64, data URI, https ' \
                   'URL, or HTML) become the submission\'s own documents, text tags become fields, and each ' \
                   'submitter receives a signing link (e-mail sent unless send_email is false). Same behaviour ' \
                   'as POST /api/submissions/pdf, /docx and /html.',
      inputSchema: {
        type: 'object',
        properties: {
          format: { type: 'string', enum: %w[pdf docx html], description: "'pdf' (default), 'docx' or 'html'" },
          name: { type: 'string', description: 'Submission name (default: the first document name)' },
          documents: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                file: { type: 'string', description: 'base64, data URI or https URL' },
                html: { type: 'string', description: 'HTML body (format html)' },
                name: { type: 'string' },
                position: { type: 'integer', description: '0-based position' },
                fields: { type: 'array', items: { type: 'object' },
                          description: 'Explicit fields: name, type, role, areas [{x, y, w, h, page (from 1)}]' }
              }
            }
          },
          submitters: {
            type: 'array',
            description: 'The signers (one submission)',
            items: {
              type: 'object',
              properties: {
                email: { type: 'string' },
                name: { type: 'string' },
                phone: { type: 'string', description: 'E.164' },
                role: { type: 'string', description: 'A role named in the text tags / fields' },
                fields: {
                  type: 'array',
                  description: 'Prefilled values (the fields become read-only)',
                  items: { type: 'object', properties: { name: { type: 'string' }, value: {} },
                           required: %w[name value] }
                }
              }
            }
          },
          send_email: { type: 'boolean', description: 'Send the signature request e-mails (default true)' },
          message: { type: 'object', properties: { subject: { type: 'string' }, body: { type: 'string' } } },
          order: { type: 'string', enum: %w[preserved random], description: 'Signing order (default preserved)' },
          merge_documents: { type: 'boolean', description: 'Merge the documents into one PDF' }
        },
        required: %w[documents submitters]
      },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true }
    }.freeze

    FORMATS = %w[pdf docx html].freeze

    def call
      authorize!(:create, Submission)

      format = tool_params[:format].presence || 'pdf'

      raise Ccn::DocumentParams::Invalid, "format must be one of #{FORMATS.join(', ')}" if FORMATS.exclude?(format)

      params = tool_params.merge('submitters' => normalized_submitters)

      raise Ccn::DocumentParams::Invalid, 'submitters[] is required' if params['submitters'].blank?

      template = Ccn::CreateSubmissionFromDocuments.transient_template(user: current_user, params:,
                                                                       format: format.to_sym)
      submissions = create_and_detach(template, params)

      Ccn::CreateSubmissionFromDocuments.discard(template)
      Ccn::CreateSubmissionFromDocuments.after_create(submissions)

      render_tool_result(submission_summary(submissions.first))
    end

    private

    def normalized_submitters
      Array.wrap(tool_params[:submitters]).map do |submitter|
        submitter = Ccn::DocumentParams.indifferent(submitter)
        attrs = submitter.slice('email', 'name', 'role', 'phone').compact_blank

        fields = Array.wrap(submitter['fields']).filter_map do |field|
          field = Ccn::DocumentParams.indifferent(field)

          next if field['name'].blank?

          { 'name' => field['name'], 'default_value' => field['value'], 'readonly' => true }
        end

        attrs['fields'] = fields if fields.present?

        attrs
      end
    end

    # Upstream's creation as the send_documents tool runs it; a failure takes the transient template (and a
    # half-built submission) away before the error reaches the client.
    def create_and_detach(template, params)
      submissions = Submissions.create_from_submitters(
        template:,
        user: current_user,
        source: :mcp,
        submitters_order: params[:order].presence || params[:submitters_order].presence || 'preserved',
        submissions_attrs: { submitters: params['submitters'] },
        params: { 'send_email' => send_email?, 'submitters' => params['submitters'],
                  'message' => params[:message] }.compact
      )

      raise Ccn::DocumentParams::Invalid, 'no submission was created: check submitters[]' if submissions.blank?

      submissions.each { |submission| Ccn::CreateSubmissionFromDocuments.detach(submission, template) }

      submissions
    rescue StandardError
      Ccn::CreateSubmissionFromDocuments.discard(template)
      raise
    end
  end
end
