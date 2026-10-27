# frozen_string_literal: true

# CCN fork — `ccn_from_email`: every e-mail about a template's submissions goes out from that template's sender,
# and replies go there unless something more specific is set.
describe SubmitterMailer do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:, email: 'luciano@chemin-neuf.org') }
  let(:template) { create(:template, account:, author: user, only_field_types: %w[text]) }
  let(:submission) { create(:submission, template:, created_by_user: user) }
  let(:submitter) do
    create(:submitter, submission:, account:, email: 'signer@example.com', uuid: template.submitters.first['uuid'])
  end

  around do |example|
    original = ENV.fetch('CCN_SMTP_FROM_DOMAINS', nil)
    ENV['CCN_SMTP_FROM_DOMAINS'] = 'cheminneuf.community,wyd2027.org'
    example.run
  ensure
    ENV['CCN_SMTP_FROM_DOMAINS'] = original
  end

  it 'keeps the upstream From and Reply-To when the template has no sender' do
    mail = described_class.invitation_email(submitter)

    expect(mail.from).to eq([user.email])
    expect(mail.reply_to).to eq([user.email])
    expect(mail[Ccn::TemplateSender::HEADER]).to be_nil
  end

  context 'with a template sender' do
    before { template.update!(preferences: { 'ccn_from_email' => '"JMJ 2027" <contact@wyd2027.org>' }) }

    it 'sends the invitation from it and directs replies to it' do
      mail = described_class.invitation_email(submitter)

      expect(mail[:from].to_s).to eq('"JMJ 2027" <contact@wyd2027.org>')
      expect(mail.reply_to).to eq(['contact@wyd2027.org'])
      expect(mail[Ccn::TemplateSender::HEADER].to_s).to eq('"JMJ 2027" <contact@wyd2027.org>')
    end

    it 'applies to reminders too' do
      submitter.update!(sent_at: 1.day.ago)

      expect(CcnSubmitterReminderMailer.reminder_email(submitter).from).to eq(['contact@wyd2027.org'])
    end

    it 'lets a submitter reply_to win' do
      submitter.update!(preferences: { 'reply_to' => 'team@wyd2027.org' })

      expect(described_class.invitation_email(submitter).reply_to).to eq(['team@wyd2027.org'])
    end

    it 'is ignored once its domain leaves CCN_SMTP_FROM_DOMAINS' do
      ENV['CCN_SMTP_FROM_DOMAINS'] = 'cheminneuf.community'

      expect(described_class.invitation_email(submitter).from).to eq([user.email])
    end
  end
end
