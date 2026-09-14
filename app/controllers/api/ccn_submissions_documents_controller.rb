# frozen_string_literal: true

module Api
  # CCN fork — POST /api/submissions/{pdf,docx,html} (specs/001-documents-by-any-route, US4). Subclasses the
  # upstream controller to reuse its private creation helpers (`create_submissions`, `submissions_params`)
  # unchanged; the upstream filters are all scoped to `create`, so none applies to these actions.
  class CcnSubmissionsDocumentsController < Api::SubmissionsController
    include Ccn::IngestionErrors

    before_action(only: %i[pdf docx html]) { authorize!(:create, Submission) }

    def pdf
      create_from(:pdf)
    end

    def docx
      create_from(:docx)
    end

    def html
      create_from(:html)
    end

    private

    def create_from(format)
      submissions = nil

      Submission.transaction do
        template = Ccn::CreateSubmissionFromDocuments.transient_template(user: current_user, params:, format:)

        params[:template_id] = template.id
        Params::SubmissionCreateValidator.call(params)

        params[:send_email] = true unless params.key?(:send_email)
        params[:send_sms] = false unless params.key?(:send_sms)

        submissions = create_submissions(template, params)
        submissions.each { |submission| Ccn::CreateSubmissionFromDocuments.detach(submission, template) }

        Ccn::CreateSubmissionFromDocuments.discard(template)
      end

      after_create(submissions)

      render json: build_documents_json(submissions)
    end

    # Same sequence as upstream `create` once the rows exist: webhooks, invitations, completion handling.
    def after_create(submissions)
      WebhookUrls.enqueue_events(submissions, 'submission.created')

      Submissions.send_signature_requests(submissions)

      submissions.each do |submission|
        if submission.submitters.all? { |s| s.viewer? || s.completed_at? } &&
           Submissions.maybe_update_completed_at(submission)
          last_submitter = submission.submitters.reject(&:viewer?).max_by(&:completed_at)
        end

        submission.submitters.each do |submitter|
          next unless submitter.completed_at?

          ProcessSubmitterCompletionJob.perform_async('submitter_id' => submitter.id,
                                                      'is_last' => submitter == last_submitter,
                                                      'send_invitation_email' => false)
        end
      end

      SearchEntries.enqueue_reindex(submissions)
    end

    # The published response: one submission object (fields included) plus its document schema.
    def build_documents_json(submissions)
      params[:include] = [params[:include], 'fields'].compact_blank.join(',')

      json = submissions.map do |submission|
        Submissions::SerializeForApi.call(submission, nil, params, with_events: false)
                                    .merge('schema' => submission.template_schema)
      end

      json.size == 1 ? json.first : json
    end
  end
end
