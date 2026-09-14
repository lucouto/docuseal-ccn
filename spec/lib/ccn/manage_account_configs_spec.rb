# frozen_string_literal: true

# CCN fork — the typed settings allow-list behind /api/ccn/account_configs (specs/002-everything-by-api).
describe Ccn::ManageAccountConfigs do
  let(:account) { create(:account) }

  def value_of(key)
    account.account_configs.find_by(key:)&.value
  end

  it 'covers the three UI allow-lists and nothing from EncryptedConfig' do
    ui_keys = AccountConfigsController::ALLOWED_KEYS + PersonalizationSettingsController::ALLOWED_KEYS +
              [AccountConfig::BCC_EMAILS, AccountConfig::SUBMITTER_REMINDERS]

    expect(described_class::KEYS.keys).to match_array(ui_keys.uniq)
    expect(described_class::KEYS.keys & EncryptedConfig::CONFIG_KEYS).to be_empty
  end

  it 'coerces booleans strictly and stores false' do
    expect(described_class.set(account, 'allow_typed_signature', '0')['value']).to be(false)
    expect(value_of('allow_typed_signature')).to be(false)
    expect(described_class.set(account, 'allow_typed_signature', 'true')['value']).to be(true)
    expect(described_class.set(account, 'allow_typed_signature', 1)['value']).to be(true)

    expect { described_class.set(account, 'allow_typed_signature', 'yes') }
      .to raise_error(Ccn::AdminInvalid, /boolean/)
    expect { described_class.set(account, 'allow_typed_signature', { a: 1 }) }
      .to raise_error(Ccn::AdminInvalid, /boolean/)

    expect(described_class.set(account, 'allow_typed_signature', nil)['value']).to be_nil
    expect(value_of('allow_typed_signature')).to be_nil
  end

  it 'stores strings and refuses other shapes for string keys' do
    expect(described_class.set(account, 'bcc_emails', 'a@x.org, b@x.org')['value']).to eq('a@x.org, b@x.org')

    expect { described_class.set(account, 'bcc_emails', true) }.to raise_error(Ccn::AdminInvalid, /string/)
    expect { described_class.set(account, 'bcc_emails', { a: 1 }) }.to raise_error(Ccn::AdminInvalid, /string/)
    expect { described_class.set(account, 'bcc_emails', 'x' * 20_001) }
      .to raise_error(Ccn::AdminInvalid, /string/)
  end

  it 'stores objects with known members only, coercing true/false and dropping blanks' do
    value = { 'subject' => 'Copie', 'body' => '', 'attach_documents' => 'true', 'enabled' => false }
    result = described_class.set(account, 'submitter_documents_copy_email', value)

    expect(result['value']).to eq('subject' => 'Copie', 'attach_documents' => true, 'enabled' => false)
    expect(result['default']).to include('subject', 'body')

    expect { described_class.set(account, 'submitter_documents_copy_email', { 'subjekt' => 'x' }) }
      .to raise_error(Ccn::AdminInvalid, /subjekt/)
    expect { described_class.set(account, 'submitter_documents_copy_email', 'plain') }
      .to raise_error(Ccn::AdminInvalid, /object/)
    expect { described_class.set(account, 'submitter_documents_copy_email', { 'subject' => [1] }) }
      .to raise_error(Ccn::AdminInvalid, /object/)

    expect(described_class.set(account, 'submitter_documents_copy_email', { 'subject' => '' })['value']).to be_nil
    expect(value_of('submitter_documents_copy_email')).to be_nil
  end

  it 'validates reminder durations against the instance table' do
    result = described_class.set(account, 'submitter_reminders',
                                 { first_duration: 'twenty_four_hours', second_duration: 'three_days' })

    expect(result['value']).to eq('first_duration' => 'twenty_four_hours', 'second_duration' => 'three_days')

    expect { described_class.set(account, 'submitter_reminders', { first_duration: '1 day' }) }
      .to raise_error(Ccn::AdminInvalid, /twenty_four_hours/)
  end

  it 'refuses unknown keys, including every encrypted configuration, without touching them' do
    %w[nope action_mailer_smtp active_storage esign_certs app_url timestamp_server_url].each do |key|
      expect { described_class.get(account, key) }.to raise_error(Ccn::AdminInvalid, /#{key}/)
      expect { described_class.set(account, key, 'x') }.to raise_error(Ccn::AdminInvalid, /#{key}/)
      expect { described_class.reset(account, key) }.to raise_error(Ccn::AdminInvalid, /#{key}/)
    end

    expect(EncryptedConfig.count).to eq(0)
    expect(AccountConfig.count).to eq(0)
  end

  it 'lists every key with its type, stored value and default' do
    described_class.set(account, 'form_with_confetti', true)

    list = described_class.list(account)

    expect(list.size).to eq(described_class::KEYS.size)
    expect(list.find { |c| c['key'] == 'form_with_confetti' }).to include('type' => 'boolean', 'value' => true)
    expect(list.find { |c| c['key'] == 'submitter_invitation_email' })
      .to include('type' => 'object', 'value' => nil, 'default' => hash_including('subject', 'body'))
    expect(list.find { |c| c['key'] == 'bcc_emails' }.keys).to contain_exactly('key', 'type', 'value')
  end
end
