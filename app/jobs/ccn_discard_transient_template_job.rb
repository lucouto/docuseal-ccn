# frozen_string_literal: true

# CCN fork — removes a transient template (POST /api/submissions/{pdf,docx,html}, research D7) that its own
# request could not destroy (Ccn::CreateSubmissionFromDocuments.discard). Only transient templates are
# touched; Sidekiq's retries cover a passing database or storage problem. A submission still attached to the
# template (creation failed before detach) goes with it, as the request intended.
class CcnDiscardTransientTemplateJob
  include Sidekiq::Job

  sidekiq_options retry: 10

  def perform(template_id)
    template = Template.find_by(id: template_id)

    return unless template
    return unless template.preferences['ccn_transient'] == true

    template.destroy!
  end
end
