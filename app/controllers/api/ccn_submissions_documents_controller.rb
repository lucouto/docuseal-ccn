# frozen_string_literal: true

module Api
  # CCN fork — POST /api/submissions/{pdf,docx,html} (specs/001-documents-by-any-route, US4). Subclasses the
  # upstream controller to reuse its private creation helpers (`create_submissions`, `submissions_params`)
  # unchanged; the upstream filters are all scoped to `create`, so none applies to these actions.
  class CcnSubmissionsDocumentsController < Api::SubmissionsController
    include Ccn::IngestionErrors

    before_action(only: %i[pdf docx html]) do
      authorize!(:create, Submission)
      authorize!(:create, Template) # a (transient) template row is created on the way
    end

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

    # No transaction spans the downloads, conversions and uploads (upstream never holds one there either):
    # until the submission is detached, everything hangs off the transient template, and destroying it
    # takes the half-built submission and the uploaded blobs down with it.
    def create_from(format)
      params[:template_id] ||= 'pending' # the validator only checks presence; the real id follows ingestion
      Params::SubmissionCreateValidator.call(params)

      template = Ccn::CreateSubmissionFromDocuments.transient_template(user: current_user, params:, format:)
      submissions = create_and_detach(template)

      discard_quietly(template)
      after_create(submissions)

      render json: build_documents_json(submissions)
    end

    def create_and_detach(template)
      params[:template_id] = template.id
      params[:send_email] = true unless params.key?(:send_email)
      params[:send_sms] = false unless params.key?(:send_sms)

      submissions = create_submissions(template, params)

      raise Ccn::DocumentParams::Invalid, 'no submission was created: check submitters[]' if submissions.empty?
      raise Ccn::NotSupportedYet, 'several submissions per request' if submissions.size > 1

      submissions.each { |submission| Ccn::CreateSubmissionFromDocuments.detach(submission, template) }

      submissions
    rescue StandardError
      Ccn::CreateSubmissionFromDocuments.discard(template) # cascades to a submission still attached to it
      raise
    end

    # The submission is complete and detached at this point: a failure here must not fail the request.
    def discard_quietly(template)
      Ccn::CreateSubmissionFromDocuments.discard(template)
    rescue StandardError => e
      Rollbar.error(e) if defined?(Rollbar)
      Rails.logger.error("CCN transient template #{template.id} not removed: #{e.class}: #{e.message}")
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
        data = Submissions::SerializeForApi.call(submission, nil, params, with_events: false)

        # embed_src is part of the published response (as in upstream's POST /submissions).
        data['submitters'].each do |submitter|
          submitter['embed_src'] = Rails.application.routes.url_helpers.submit_form_url(slug: submitter['slug'],
                                                                                        **Docuseal.default_url_options)
        end

        data.merge('schema' => submission.template_schema)
      end

      json.size == 1 ? json.first : json
    end
  end
end
