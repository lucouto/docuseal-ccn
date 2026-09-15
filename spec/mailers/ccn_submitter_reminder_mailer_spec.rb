# frozen_string_literal: true

# CCN fork — Stage 4, US1 (specs/003-p1-features, research D5): subject/body resolution order and the
# invitation mailer's shared rules (reply-to, from, locale).
describe CcnSubmitterReminderMailer do
  let(:account) { create(:account) }
  let(:template) { create(:template, account:) }
  let(:submission) { create(:submission, template:) }
  let(:submitter) do
    create(:submitter, submission:, account:, email: 'signer@example.com', sent_at: 1.day.ago,
                       uuid: submission.template_submitters.first['uuid'])
  end

  before { create(:user, account:) } # Account#default_template_folder needs an author to assign templates to

  it 'uses the template preference when present' do
    template.update!(preferences: { 'invitation_reminder_email_subject' => 'Template subject',
                                    'invitation_reminder_email_body' => 'Template body' })

    mail = described_class.reminder_email(submitter)

    expect(mail.subject).to eq('Template subject')
    expect(mail.body.encoded).to include('Template body')
  end

  it 'falls back to the account config when the template has no override' do
    AccountConfig.create!(account:, key: AccountConfig::SUBMITTER_INVITATION_REMINDER_EMAIL_KEY,
                          value: { 'subject' => 'Account subject', 'body' => 'Account body' })

    mail = described_class.reminder_email(submitter)

    expect(mail.subject).to eq('Account subject')
    expect(mail.body.encoded).to include('Account body')
  end

  it 'falls back to AccountConfig::DEFAULT_VALUES when neither is set' do
    default = AccountConfig::DEFAULT_VALUES.fetch(AccountConfig::SUBMITTER_INVITATION_REMINDER_EMAIL_KEY).call

    mail = described_class.reminder_email(submitter)

    expect(mail.subject).to eq(default['subject'])
    expect(mail.body.encoded).to include('You have been invited to sign the')
  end

  it 'resolves the default text in the account locale, not the process locale' do
    account.update!(locale: 'fr-FR')

    # .message forces the mailer action to run here: ActionMailer is lazy, so a bare call would be evaluated
    # outside this block and the locale under test would not be the one in effect.
    mail = I18n.with_locale(:en) { described_class.reminder_email(submitter).message }

    expect(mail.subject).to eq(I18n.t(:you_are_invited_to_sign_a_document, locale: 'fr-FR'))
    expect(mail.subject).not_to eq(I18n.t(:you_are_invited_to_sign_a_document, locale: :en))
  end

  it 'is addressed to the submitter and records a reminder tag' do
    mail = described_class.reminder_email(submitter)

    expect(mail.to).to eq([submitter.email])
    expect(mail.message.instance_variable_get(:@message_metadata)).to include('tag' => 'submitter_reminder')
  end

  it 'replaces e-mail variables in the subject' do
    AccountConfig.create!(account:, key: AccountConfig::SUBMITTER_INVITATION_REMINDER_EMAIL_KEY,
                          value: { 'subject' => 'Reminder: {{template.name}}', 'body' => 'Body' })

    mail = described_class.reminder_email(submitter)

    expect(mail.subject).to eq("Reminder: #{template.name}")
  end
end
