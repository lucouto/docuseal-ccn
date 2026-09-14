# frozen_string_literal: true

# CCN fork — Stage 4, US1 (specs/003-p1-features, research D5): a flat class next to SubmitterMailer (which
# stays untouched, principle I) reusing its private helpers. Resolution order for subject/body: the template's
# own reminder preference, then the account's reminder e-mail config, then AccountConfig::DEFAULT_VALUES (the
# same default text the invitation e-mail uses).
class CcnSubmitterReminderMailer < SubmitterMailer
  def reminder_email(submitter)
    @current_account = submitter.submission.account
    @submitter = submitter

    template_preferences = @submitter.template&.preferences || {}

    @subject = template_preferences['invitation_reminder_email_subject'].presence
    @body = template_preferences['invitation_reminder_email_body'].presence

    @email_config = AccountConfigs.find_for_account(@current_account,
                                                    AccountConfig::SUBMITTER_INVITATION_REMINDER_EMAIL_KEY)

    @subject ||= @email_config&.value&.dig('subject').presence
    @body ||= fetch_config_email_body(@email_config, @submitter)

    assign_message_metadata('submitter_reminder', @submitter)

    reply_to = build_submitter_reply_to(@submitter, email_config: @email_config)

    maybe_set_custom_domain(@submitter)

    I18n.with_locale(@current_account.locale) do
      # DEFAULT_VALUES translates on call, so it has to resolve in the account's locale — outside this block
      # a French account with no override would get the process locale's text (normally English).
      default = AccountConfig::DEFAULT_VALUES.fetch(AccountConfig::SUBMITTER_INVITATION_REMINDER_EMAIL_KEY).call
      @subject ||= default['subject']
      @body ||= default['body']

      subject = ReplaceEmailVariables.call(@subject, submitter:)

      mail(
        to: @submitter.friendly_name,
        from: from_address_for_submitter(submitter),
        subject:,
        reply_to:
      )
    end
  end
end
