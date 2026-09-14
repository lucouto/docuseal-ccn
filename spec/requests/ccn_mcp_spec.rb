# frozen_string_literal: true

# CCN fork — Stage 3, user story 5 (specs/002-everything-by-api): the fork's API as MCP tools on /mcp, next
# to upstream's five (which have no upstream tests).
describe 'CCN MCP tools' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:) }
  let(:token) { admin.mcp_tokens.create!(name: 'spec') }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}", 'Content-Type' => 'application/json' } }
  let(:fixtures) { Rails.root.join('spec/fixtures') }
  let(:pdf_base64) { Base64.strict_encode64(fixtures.join('ccn/fieldtags.pdf').binread) }
  let(:sample_base64) { Base64.strict_encode64(fixtures.join('sample-document.pdf').binread) }
  let(:fork_tools) do
    %w[create_template_from_documents update_template_documents merge_templates create_submission_from_documents
       manage_users manage_webhooks account_config set_template_preferences]
  end

  before do
    create(:account_config, account:, key: AccountConfig::ENABLE_MCP_KEY, value: true)
  end

  def rpc(method, params = {})
    post '/mcp', headers:, params: { jsonrpc: '2.0', id: 7, method:, params: }.to_json

    response.parsed_body
  end

  # => [error?, data] — the tool result's text content parsed back when it is JSON
  def tool(name, arguments)
    result = rpc('tools/call', { name:, arguments: })['result']
    text = result.dig('content', 0, 'text')

    [result['isError'] == true, parse(text)]
  end

  def parse(text)
    JSON.parse(text)
  rescue JSON::ParserError
    text
  end

  it 'lists the fork tools next to upstream ones, each with a schema' do
    body = rpc('tools/list')

    expect(response).to have_http_status(:ok)
    expect(body['id']).to eq(7)
    names = body['result']['tools'].pluck('name')
    expect(names).to include(*fork_tools, 'search_templates', 'create_template', 'send_documents')
    expect(body['result']['tools'].all? { |t| t['inputSchema'].is_a?(Hash) && t['description'].present? }).to be(true)
  end

  it 'refuses the tools when MCP is disabled for the account or the token is missing' do
    account.account_configs.where(key: AccountConfig::ENABLE_MCP_KEY).destroy_all

    rpc('tools/list')
    expect(response).to have_http_status(:forbidden)

    post '/mcp', headers: { 'Content-Type' => 'application/json' },
                 params: { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'creates, updates and merges templates from documents' do
    error, data = tool('create_template_from_documents',
                       { name: 'Lease', folder_name: 'MCP', documents: [{ name: 'lease', file: pdf_base64 }] })

    expect(error).to be(false)
    expect(data).to include('name' => 'Lease', 'folder_name' => 'MCP', 'documents' => ['lease'])
    expect(data['fields'].pluck('name')).to include('Text Field', 'Signature')
    expect(data['roles']).to include('First Party', 'Signer2')
    expect(data['edit_url']).to include("/templates/#{data['id']}/edit")

    error, updated = tool('update_template_documents',
                          { template_id: data['id'], documents: [{ name: 'annex', file: sample_base64 }] })

    expect(error).to be(false)
    expect(updated['documents']).to eq(%w[lease annex])

    other = create(:template, account:, author: admin)
    error, merged = tool('merge_templates', { template_ids: [data['id'], other.id], name: 'Bundle' })

    expect(error).to be(false)
    expect(merged['name']).to eq('Bundle')
    expect(merged['documents'].size).to eq(3)

    stranger = create(:user)
    foreign = create(:template, account: stranger.account, author: stranger)

    error, message = tool('merge_templates', { template_ids: [data['id'], foreign.id] })
    expect(error).to be(true)
    expect(message).to include('Template not found')

    error, message = tool('update_template_documents', { template_id: foreign.id, documents: [] })
    expect(error).to be(true)
    expect(message).to eq('Not found')
  end

  it 'creates a template-less submission and sends the requests' do
    templates_before = Template.count
    jobs_before = SendSubmitterInvitationEmailJob.jobs.size

    error, data = tool('create_submission_from_documents',
                       { documents: [{ name: 'lease', file: pdf_base64 }],
                         submitters: [{ email: 'first@example.com', role: 'First Party', name: 'Ann' },
                                      { email: 'second@example.com', role: 'Signer2' }] })

    expect(SendSubmitterInvitationEmailJob.jobs.size).to eq(jobs_before + 1) # preserved order: first signer only

    expect(error).to be(false)
    expect(data).to include('status' => 'pending', 'name' => 'lease', 'documents' => ['lease'])
    expect(data['submitters'].pluck('role')).to eq(['First Party', 'Signer2'])
    expect(data['submitters'].first['embed_src']).to include("/s/#{data['submitters'].first['slug']}")
    expect(Submission.find(data['id']).template_id).to be_nil
    expect(Template.count).to eq(templates_before)

    error, message = tool('create_submission_from_documents',
                          { documents: [{ name: 'plain', file: sample_base64 }],
                            submitters: [{ email: 'x@example.com' }] })
    expect(error).to be(true)
    expect(message).to match(/no fields/)
    expect(Template.count).to eq(templates_before)
  end

  it 'manages users and webhooks with the REST rules and messages' do
    error, users = tool('manage_users', { action: 'list' })
    expect(error).to be(false)
    expect(users.pluck('id')).to eq([admin.id])

    error, invited = tool('manage_users', { action: 'invite', email: 'new@example.com', first_name: 'New',
                                            send_email: false })
    expect(error).to be(false)
    expect(invited).to include('email' => 'new@example.com', 'role' => 'admin')

    error, archived = tool('manage_users', { action: 'archive', id: invited['id'] })
    expect(error).to be(false)
    expect(archived['archived_at']).to be_present

    error, message = tool('manage_users', { action: 'archive', id: admin.id })
    expect(error).to be(true)
    expect(message).to eq(I18n.t('ccn_self_change_refused'))

    error, webhook = tool('manage_webhooks', { action: 'create', url: 'https://n8n.example.com/hook',
                                               events: ['form.completed'], secret: { key: 'X-Token', value: 's' } })
    expect(error).to be(false)
    expect(webhook).to include('events' => ['form.completed'], 'secret_key' => 'X-Token')
    expect(webhook).not_to have_key('secret')

    error, revealed = tool('manage_webhooks', { action: 'reveal', id: webhook['id'] })
    expect(error).to be(false)
    expect(revealed['secret']).to eq('X-Token' => 's')
    expect(revealed['hmac_secret']).to be_present

    error, message = tool('manage_webhooks', { action: 'update', id: webhook['id'], events: ['form.nope'] })
    expect(error).to be(true)
    expect(message).to include('form.nope')

    error, deleted = tool('manage_webhooks', { action: 'delete', id: webhook['id'] })
    expect(error).to be(false)
    expect(deleted).to eq('id' => webhook['id'], 'deleted' => true)
  end

  it 'manages account configs and template preferences with the REST rules and messages' do
    error, config = tool('account_config', { action: 'set', key: 'submitter_reminders',
                                             value: { first_duration: 'twenty_four_hours' } })
    expect(error).to be(false)
    expect(config['value']).to eq('first_duration' => 'twenty_four_hours')

    error, message = tool('account_config', { action: 'set', key: 'action_mailer_smtp', value: 'x' })
    expect(error).to be(true)
    expect(message).to eq(I18n.t('ccn_unknown_setting', key: 'action_mailer_smtp'))

    error, list = tool('account_config', { action: 'list' })
    expect(error).to be(false)
    expect(list.size).to eq(Ccn::ManageAccountConfigs::KEYS.size)

    template = create(:template, account:, author: admin)
    error, prefs = tool('set_template_preferences',
                        { template_id: template.id,
                          preferences: { request_email_subject: 'Signez', require_email_2fa: true } })
    expect(error).to be(false)
    expect(prefs['preferences']).to eq('request_email_subject' => 'Signez', 'require_email_2fa' => true)
    expect(template.reload.preferences['request_email_subject']).to eq('Signez')

    error, message = tool('set_template_preferences', { template_id: template.id, preferences: { colour: 'red' } })
    expect(error).to be(true)
    expect(message).to eq(I18n.t('ccn_unknown_preference', key: 'colour'))
  end
end
