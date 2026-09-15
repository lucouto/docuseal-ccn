# frozen_string_literal: true

# CCN fork — Stage 4, US4 (specs/003-p1-features): the "Upload list" tab of a template's Send page. A
# spreadsheet of signers becomes one submission per row through Submissions.create_from_submitters — the same
# path POST /api/submissions takes — so the two agree on what a submission is.
#
# Two steps on purpose: nobody should send forty e-mails from a file they have not seen read back. The rows
# travel from the preview to the send in a signed payload rather than a re-upload, so the page the user
# confirms is the one that gets sent, and the payload cannot be edited on the way.
class CcnSubmissionsListsController < ApplicationController
  PAYLOAD_PURPOSE = :ccn_submissions_list
  PAYLOAD_TTL = 1.hour

  load_and_authorize_resource :template
  before_action { authorize!(:create, Submission) }
  before_action :ensure_template_accepts_a_list

  def preview
    @result = Ccn::SubmissionsLists.parse(params[:file], @template)
    @send_email = params[:send_email].to_s
    @payload = sign(@result['submissions_attrs']) if @result['errors'].blank? && @result['rows_count'].positive?

    render :preview, layout: 'plain'
  rescue Ccn::SubmissionsLists::Invalid => e
    redirect_to new_template_submission_path(@template), alert: e.message
  end

  def create
    submissions_attrs = verify(params[:payload])

    return redirect_to template_path(@template), alert: I18n.t('ccn_list_expired') if submissions_attrs.nil?

    submissions = create_submissions(submissions_attrs)

    WebhookUrls.enqueue_events(submissions, 'submission.created')
    Submissions.send_signature_requests(submissions)
    SearchEntries.enqueue_reindex(submissions)

    redirect_to template_path(@template), notice: I18n.t('new_recipients_have_been_added')
  rescue Submissions::CreateFromSubmitters::BaseError, Submitters::NormalizeValues::BaseError => e
    redirect_to template_path(@template), alert: e.message
  end

  private

  # Upstream's Send page refuses an archived template, and only offers the list tab when the template has no
  # variables schema (there is nowhere to put the variables in a spreadsheet). Both apply here too — reaching
  # this controller directly must not do what that page would not.
  def ensure_template_accepts_a_list
    return redirect_to template_path(@template), alert: I18n.t('template_has_been_archived') if @template.archived_at?
    return if @template.variables_schema.blank?

    redirect_to new_template_submission_path(@template), alert: I18n.t('ccn_list_not_available')
  end

  # One transaction for the whole file: FR-010 says a bad file sends nothing, and a failure half way through
  # (a duplicate address under `validate_unique_submitters`, say) would otherwise leave the earlier rows saved
  # and marked sent while the person is told the send was refused.
  def create_submissions(submissions_attrs)
    submissions_attrs, _attachments, new_fields =
      Submissions::NormalizeParamUtils.normalize_submissions_params!(submissions_attrs, @template, add_fields: true)

    Submission.transaction do
      Submissions.create_from_submitters(
        # Upstream's `_submitters_order` forces "preserved" for a template that signs in order, and the
        # checkbox it offers otherwise is checked by default. A list has no checkbox, so it always preserves:
        # `random` on a sequential template would invite the counter-signatory before the first party has
        # signed, which the ordinary Send page cannot do.
        template: @template, user: current_user, source: :invite, submitters_order: 'preserved',
        submissions_attrs:, new_fields:,
        params: { 'send_email' => params[:send_email], 'send_completed_email' => true }
      )
    end
  end

  def sign(submissions_attrs)
    ApplicationRecord.signed_id_verifier.generate(
      { 'template_id' => @template.id, 'submissions' => submissions_attrs.as_json },
      expires_in: PAYLOAD_TTL, purpose: PAYLOAD_PURPOSE
    )
  end

  # nil when the payload is missing, tampered with, expired, or was signed for another template — the caller
  # sends the user back rather than creating anything.
  def verify(payload)
    data = ApplicationRecord.signed_id_verifier.verified(payload.to_s, purpose: PAYLOAD_PURPOSE)

    return if data.blank? || data['template_id'] != @template.id

    Array.wrap(data['submissions']).map(&:with_indifferent_access).presence
  end
end
