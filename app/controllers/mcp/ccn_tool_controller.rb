# frozen_string_literal: true

module Mcp
  # CCN fork — shared base of the fork's MCP tools (specs/002-everything-by-api, US5, FR-009). No SCHEMA:
  # not a tool itself. Arguments come in as an indifferent hash; failures are tool errors with the REST message.
  class CcnToolController < McpBaseController
    include Ccn::McpToolErrors

    private

    def tool_params
      @tool_params ||= Ccn::DocumentParams.indifferent(mcp_params)
    end

    def find_template(id)
      raise Ccn::DocumentParams::Invalid, 'template_id is required' if id.blank?

      Template.accessible_by(current_ability).find(id)
    end

    def send_email?
      !tool_params.key?(:send_email) || Ccn::DocumentParams.boolean(tool_params[:send_email])
    end

    # A conversational summary of a template: what a user needs to send it or open the builder.
    def template_summary(template)
      roles = template.submitters.index_by { |submitter| submitter['uuid'] }

      {
        id: template.id, name: template.name, external_id: template.external_id,
        folder_name: template.folder&.full_name, edit_url: edit_template_url(template),
        roles: template.submitters.pluck('name'), documents: template.schema.pluck('name'),
        fields: template.fields.map do |field|
          { name: field['name'], type: field['type'], role: roles.dig(field['submitter_uuid'], 'name') }
        end
      }
    end

    def submission_summary(submission)
      roles = submission.template_submitters.index_by { |submitter| submitter['uuid'] }

      {
        id: submission.id, status: 'pending', name: submission.name,
        documents: submission.template_schema.pluck('name'),
        submitters: submission.submitters.map do |submitter|
          { id: submitter.id, email: submitter.email, name: submitter.name, role: roles.dig(submitter.uuid, 'name'),
            slug: submitter.slug, embed_src: submit_form_url(slug: submitter.slug) }
        end
      }
    end
  end
end
