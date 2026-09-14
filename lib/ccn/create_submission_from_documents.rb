# frozen_string_literal: true

module Ccn
  # POST /api/submissions/{pdf,docx,html} (US4, FR-013, research D7). Upstream's submission creation needs a
  # template, the published response has none: the documents first become a saved *transient* template
  # (step 1), the controller runs upstream's own creation on it (step 2), then the submission takes the
  # snapshot and the documents for itself and the transient template is destroyed (step 3).
  module CreateSubmissionFromDocuments
    module_function

    # Step 1. `documents[].position` orders the documents; `merge_documents` folds them into one PDF. The
    # published operations create ONE submission (`submitters[]`); upstream's `emails` / `submissions[]`
    # forms would create several, which the single document set cannot serve.
    def transient_template(user:, params:, format:)
      raise Ccn::NotSupportedYet, 'template_ids' if params[:template_ids].present?
      raise Ccn::NotSupportedYet, 'variables' if params[:variables].present?

      if params[:submitters].blank?
        raise Ccn::NotSupportedYet, 'emails / submissions[] (one submission per request: pass submitters[])'
      end

      documents = ordered_documents(params)
      files =
        if format == :html
          Ccn::HtmlDocuments.files_from(params, documents:)
        else
          Ccn::DocumentParams.files_from(documents)
        end

      template = Ccn::CreateTemplateFromDocuments.call(user:, params:, files:, transient: true,
                                                       documents: format == :html ? [] : documents)

      if Ccn::DocumentParams.boolean(params[:merge_documents])
        Ccn::UpdateTemplateDocuments.merge(template)
        template.save!
      end

      if template.fields.blank?
        raise Ccn::DocumentParams::Invalid, 'documents contain no fields: add {{text tags}} or fields[]'
      end

      template
    end

    # Documents with a `position` come first, in position order; the others follow in input order.
    def ordered_documents(params)
      documents = Array.wrap(params[:documents]).map { |document| Ccn::DocumentParams.indifferent(document) }

      documents.each_with_index.sort_by do |document, index|
        position = Integer(document[:position].to_s, 10, exception: false)

        position ? [0, position, index] : [1, index, index]
      end.map(&:first)
    end

    # Step 3. The submission keeps its own snapshot (schema, fields, roles) and the documents themselves; the
    # template row goes. Only the documents the schema references move (a merge leaves its sources behind).
    def detach(submission, template)
      submission.template_schema = template.schema if submission.template_schema.blank?
      submission.template_fields = template.fields if submission.template_fields.blank?
      submission.template_submitters = template.submitters if submission.template_submitters.blank?
      submission.name = template.name if submission.name.blank?

      uuids = template.schema.pluck('attachment_uuid')
      template.documents_attachments.where(uuid: uuids).find_each do |attachment|
        attachment.update!(record: submission, name: 'documents')
      end

      submission.template_id = nil
      submission.save!
    end

    # Destroyed through a fresh instance: the one used for creation still holds the submission in its loaded
    # `submissions` association, which `dependent: :destroy` would take down with it.
    def discard(template)
      Template.find(template.id).destroy!
    end
  end
end
