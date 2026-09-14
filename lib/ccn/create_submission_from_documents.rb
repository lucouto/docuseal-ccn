# frozen_string_literal: true

module Ccn
  # POST /api/submissions/{pdf,docx,html} (US4, FR-013, research D7). Upstream's submission creation needs a
  # template, the published response has none: the documents first become a saved *transient* template
  # (step 1), the controller runs upstream's own creation on it (step 2), then the submission takes the
  # snapshot and the documents for itself and the transient template is destroyed (step 3).
  module CreateSubmissionFromDocuments
    # Upstream's other creation forms make several submissions per request; they are refused with an
    # explicit 422 even next to `submitters[]` (the validator would then skip the per-submitter checks, and
    # the single document set can only be attached once).
    MULTI_SUBMISSION_KEYS = %i[emails email submissions submission].freeze
    SINGLE_SUBMISSION_HINT = 'emails / submission / submissions[] (one submission per request: pass submitters[])'

    module_function

    # Step 1. `documents[].position` orders the documents; `merge_documents` folds them into one PDF. The
    # published operations create ONE submission (`submitters[]`); upstream's `emails` / `submissions[]`
    # forms would create several, which the single document set cannot serve.
    def transient_template(user:, params:, format:)
      raise Ccn::NotSupportedYet, 'template_ids' if params[:template_ids].present?
      raise Ccn::NotSupportedYet, 'variables' if params[:variables].present?

      if params[:submitters].blank? || MULTI_SUBMISSION_KEYS.any? { |key| params[key].present? }
        raise Ccn::NotSupportedYet, SINGLE_SUBMISSION_HINT
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

      finish_transient(template, params)
    end

    # Once the transient template exists, any further refusal must take it (and its blobs) away again.
    def finish_transient(template, params)
      if Ccn::DocumentParams.boolean(params[:merge_documents])
        Ccn::UpdateTemplateDocuments.merge(template)
        template.save!
      end

      if template.fields.blank?
        raise Ccn::DocumentParams::Invalid, 'documents contain no fields: add {{text tags}} or fields[]'
      end

      template
    rescue StandardError
      discard(template)
      raise
    end

    # `documents[].position` is a 0-based index into the final order (as in PUT /templates/:id/documents): the
    # documents without one keep their input order and each positioned document is inserted at its position,
    # lowest first, clamped to the list.
    def ordered_documents(params)
      documents = Array.wrap(params[:documents]).map { |document| Ccn::DocumentParams.indifferent(document) }
      positioned, ordered = documents.partition { |document| position_of(document) }

      positioned.sort_by.with_index { |document, index| [position_of(document), index] }.each do |document|
        ordered.insert(position_of(document).clamp(0, ordered.size), document)
      end

      ordered
    end

    def position_of(document)
      Integer(document[:position].to_s, 10, exception: false)
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
    # `submissions` association, which `dependent: :destroy` would take down with it. Never raises: the callers
    # are either cleaning up after an error that must reach the client or finishing a request that already
    # succeeded — a template that resists is archived anyway (never listed) and CcnDiscardTransientTemplateJob
    # retries.
    def discard(template)
      Template.find_by(id: template.id)&.destroy!
    rescue StandardError => e
      report_discard_failure(template, e)
    end

    def report_discard_failure(template, error)
      Rollbar.error(error) if defined?(Rollbar)
      Rails.logger.error("CCN transient template #{template.id} not removed: #{error.class}: #{error.message}")

      CcnDiscardTransientTemplateJob.perform_in(1.minute, template.id)
    rescue StandardError => e
      Rails.logger.error("CCN transient template #{template.id}: retry not enqueued: #{e.class}: #{e.message}")
    end
  end
end
