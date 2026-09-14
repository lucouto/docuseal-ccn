# frozen_string_literal: true

# CCN fork — Stage 3, user story 3 (specs/002-everything-by-api): account settings by API.
describe 'CCN account configs API' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': admin.access_token.token, 'Content-Type': 'application/json' } }

  def json
    response.parsed_body
  end

  def api(method, path, body = nil)
    public_send(method, path, headers:, params: body&.to_json)
  end

  it 'lists every allowed key with type, value and default, and reads one' do
    api :get, '/api/ccn/account_configs'

    expect(response).to have_http_status(:ok)
    expect(json['data'].pluck('key')).to match_array(Ccn::ManageAccountConfigs::KEYS.keys)
    expect(json['data'].pluck('type').uniq).to contain_exactly('boolean', 'string', 'object')
    expect(json['data'].find { |c| c['key'] == 'submitter_invitation_email' }['default']).to include('subject', 'body')
    expect(json['data'].pluck('key')).not_to include(*EncryptedConfig::CONFIG_KEYS)

    api :get, '/api/ccn/account_configs/allow_typed_signature'
    expect(json).to eq('key' => 'allow_typed_signature', 'type' => 'boolean', 'value' => nil)
  end

  it 'sets, reads back and resets a boolean, a string and an object' do
    api :put, '/api/ccn/account_configs/allow_typed_signature', { value: '0' }
    expect(response).to have_http_status(:ok)
    expect(json).to include('value' => false)
    expect(account.account_configs.find_by(key: 'allow_typed_signature').value).to be(false)

    api :put, '/api/ccn/account_configs/bcc_emails', { value: 'archive@example.com' }
    expect(json).to include('value' => 'archive@example.com')

    api :put, '/api/ccn/account_configs/submitter_invitation_email',
        { value: { subject: 'Merci de signer {{template.name}}', body: 'Bonjour {{submitter.link}}' } }
    expect(response).to have_http_status(:ok)
    expect(json['value']).to eq('subject' => 'Merci de signer {{template.name}}',
                                'body' => 'Bonjour {{submitter.link}}')

    api :put, '/api/ccn/account_configs/submitter_reminders',
        { value: { first_duration: 'twenty_four_hours', second_duration: 'three_days' } }
    expect(response).to have_http_status(:ok)
    expect(json['value']).to eq('first_duration' => 'twenty_four_hours', 'second_duration' => 'three_days')

    api :get, '/api/ccn/account_configs/bcc_emails'
    expect(json['value']).to eq('archive@example.com')

    api :delete, '/api/ccn/account_configs/allow_typed_signature'
    expect(response).to have_http_status(:ok)
    expect(json).to include('value' => nil)
    expect(account.account_configs.exists?(key: 'allow_typed_signature')).to be(false)

    api :put, '/api/ccn/account_configs/bcc_emails', { value: '' }
    expect(json['value']).to be_nil
    expect(account.account_configs.exists?(key: 'bcc_emails')).to be(false)
  end

  it 'refuses a wrong type, an unknown member, an unknown key and every encrypted configuration' do
    api :put, '/api/ccn/account_configs/allow_typed_signature', { value: 'maybe' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']).to eq(I18n.t('ccn_invalid_setting_value', key: 'allow_typed_signature', type: 'boolean'))

    api :put, '/api/ccn/account_configs/form_completed_message', { value: { title: 'Done', colour: 'red' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']).to include('colour')

    api :put, '/api/ccn/account_configs/submitter_reminders', { value: { first_duration: 'tomorrow' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']).to include('one_hour')

    api :get, '/api/ccn/account_configs/nope'
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']).to eq(I18n.t('ccn_unknown_setting', key: 'nope'))

    EncryptedConfig::CONFIG_KEYS.each do |key|
      api :get, "/api/ccn/account_configs/#{key}"
      expect(response).to have_http_status(:unprocessable_content)

      api :put, "/api/ccn/account_configs/#{key}", { value: 'x' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    expect(EncryptedConfig.count).to eq(0)
    expect(AccountConfig.count).to eq(0)
  end

  it 'toggles enable_mcp like the UI does' do
    api :put, '/api/ccn/account_configs/enable_mcp', { value: true }
    expect(response).to have_http_status(:ok)
    expect(account.account_configs.find_by(key: AccountConfig::ENABLE_MCP_KEY).value).to be(true)

    api :put, '/api/ccn/account_configs/enable_mcp', { value: false }
    expect(account.account_configs.find_by(key: AccountConfig::ENABLE_MCP_KEY).value).to be(false)
  end

  it 'refuses a missing token' do
    get '/api/ccn/account_configs'

    expect(response).to have_http_status(:unauthorized)
  end
end
