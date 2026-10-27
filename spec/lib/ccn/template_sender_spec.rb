# frozen_string_literal: true

# CCN fork — per-template sender (`ccn_from_email`, CCN_SMTP_FROM_DOMAINS): the address check, and the hand-off
# from the mailer to ActionMailerConfigsInterceptor, which would otherwise replace the From with SMTP_FROM.
describe Ccn::TemplateSender do
  around do |example|
    original = ENV.fetch('CCN_SMTP_FROM_DOMAINS', nil)
    ENV['CCN_SMTP_FROM_DOMAINS'] = 'cheminneuf.community, WYD2027.org'
    example.run
  ensure
    ENV['CCN_SMTP_FROM_DOMAINS'] = original
  end

  describe '.normalize' do
    it 'accepts one address on an allowed domain, with or without a display name' do
      expect(described_class.normalize('JMJ 2027 <contact@wyd2027.org>')).to eq('"JMJ 2027" <contact@wyd2027.org>')
      expect(described_class.normalize('docuseal@cheminneuf.community')).to eq('docuseal@cheminneuf.community')
    end

    it 'refuses other domains, lists and garbage' do
      expect(described_class.normalize('x@chemin-neuf.org')).to be_nil
      expect(described_class.normalize('a@wyd2027.org, b@wyd2027.org')).to be_nil
      expect(described_class.normalize('not an address')).to be_nil
      expect(described_class.normalize('<<<')).to be_nil
    end

    it 'refuses everything when CCN_SMTP_FROM_DOMAINS is unset' do
      ENV.delete('CCN_SMTP_FROM_DOMAINS')

      expect(described_class.normalize('contact@wyd2027.org')).to be_nil
    end
  end

  describe 'ActionMailerConfigsInterceptor in production' do
    let(:message) do
      Mail.new do
        from '"Luciano" <luciano@chemin-neuf.org>'
        to 'signer@example.com'
      end
    end

    around do |example|
      original = ENV.fetch('SMTP_FROM', nil)
      ENV['SMTP_FROM'] = 'docuseal@cheminneuf.community'
      example.run
    ensure
      ENV['SMTP_FROM'] = original
    end

    before do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Docuseal).to receive(:demo?).and_return(false)
      allow(Rails.application.config.action_mailer).to receive(:delivery_method).and_return(:smtp)
    end

    it 'uses the template sender instead of SMTP_FROM and strips the hand-off header' do
      message[described_class::HEADER] = '"WYD 2027" <contact@wyd2027.org>'

      ActionMailerConfigsInterceptor.delivering_email(message)

      expect(message[:from].to_s).to eq('"WYD 2027" <contact@wyd2027.org>')
      expect(message[described_class::HEADER]).to be_nil
    end

    it 'keeps SMTP_FROM, with the sender name, when there is no template sender' do
      ActionMailerConfigsInterceptor.delivering_email(message)

      expect(message[:from].to_s).to eq('"Luciano" <docuseal@cheminneuf.community>')
    end

    it 'ignores a header naming a domain that is not allowed' do
      message[described_class::HEADER] = 'someone@example.com'

      ActionMailerConfigsInterceptor.delivering_email(message)

      expect(message.from).to eq(['docuseal@cheminneuf.community'])
      expect(message[described_class::HEADER]).to be_nil
    end
  end
end
