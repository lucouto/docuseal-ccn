# frozen_string_literal: true

# CCN fork — the fork's own API description (docs/openapi-ccn.json, specs/002-everything-by-api FR-010): every
# documented operation is routed by this build and answers a 200 that matches its schema. The upstream
# description keeps its own contract spec (openapi_contract_spec.rb).
describe 'CCN OpenAPI contract (docs/openapi-ccn.json)' do
  let(:spec_path) { Rails.root.join('docs/openapi-ccn.json') }
  let(:operations) { OpenapiContract.operations(spec_path) }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': admin.access_token.token, 'Content-Type': 'application/json' } }
  let(:template) { create(:template, account:, author: admin) }

  def json
    response.parsed_body
  end

  def api(method, path, body = nil)
    public_send(method, path, headers:, params: body&.to_json)
  end

  it 'is OpenAPI 3.1 with upstream\'s security scheme and documents only routable operations' do
    document = OpenapiContract.spec(spec_path)

    expect(document['openapi']).to eq('3.1.0')
    expect(document.dig('components', 'securitySchemes', 'AuthToken')).to eq('type' => 'apiKey', 'in' => 'header',
                                                                             'name' => 'X-Auth-Token')
    expect(operations.size).to eq(29)
    expect(operations.map { |op| op[:operation]['operationId'] }.uniq.size).to eq(29)

    unrouted = operations.reject { |op| OpenapiContract.routable?(op[:method], op[:path]) }
    expect(unrouted.map { |op| "#{op[:method].upcase} #{op[:path]}" }).to be_empty

    operations.each do |op|
      expect(op[:operation]['security']).to eq([{ 'AuthToken' => [] }]), "#{op[:path]} lacks AuthToken"
      expect(op[:operation].dig('responses', '422')).to be_present, "#{op[:path]} lacks the 422 response"
    end
  end

  it 'answers every documented operation with a conforming 200' do
    allow(Templates::DetectFields).to receive(:call) do |_io, attachment:, page_number:, **, &block|
      area = { x: 0.61, y: 0.93, w: 0.1, h: 0.03, page: page_number || 0, attachment_uuid: attachment.uuid }
      fields = [{ uuid: SecureRandom.uuid, type: 'text', required: false, preferences: {}, areas: [area] }]
      block&.call([attachment.uuid, page_number || 0, fields])
      [fields, nil]
    end

    submission = create(:submission, :with_submitters, template:)
    submission.submitters.first.update!(completed_at: Time.current)
    ids = {}

    plan = [
      ['post', '/ccn/users', -> { api :post, '/api/ccn/users', { email: 'c@example.com', send_email: false } }],
      ['get', '/ccn/users', -> { api :get, '/api/ccn/users' }],
      ['get', '/ccn/users/{id}', -> { api :get, "/api/ccn/users/#{ids[:user]}" }],
      ['put', '/ccn/users/{id}', -> { api :put, "/api/ccn/users/#{ids[:user]}", { first_name: 'C' } }],
      ['post', '/ccn/users/{id}/reset_password', -> { api :post, "/api/ccn/users/#{ids[:user]}/reset_password" }],
      ['delete', '/ccn/users/{id}', -> { api :delete, "/api/ccn/users/#{ids[:user]}" }],
      ['post', '/ccn/webhooks', -> { api :post, '/api/ccn/webhooks', { url: 'https://n8n.example.com/h' } }],
      ['get', '/ccn/webhooks', -> { api :get, '/api/ccn/webhooks' }],
      ['get', '/ccn/webhooks/{id}', -> { api :get, "/api/ccn/webhooks/#{ids[:webhook]}" }],
      ['put', '/ccn/webhooks/{id}',
       -> { api :put, "/api/ccn/webhooks/#{ids[:webhook]}", { events: ['form.completed'] } }],
      ['get', '/ccn/webhooks/{id}/secret', -> { api :get, "/api/ccn/webhooks/#{ids[:webhook]}/secret" }],
      ['get', '/ccn/webhooks/{id}/events', lambda {
        event = WebhookEvent.create!(webhook_url_id: ids[:webhook], account:, event_type: 'form.completed',
                                     record: submission.submitters.first, status: 'error')
        WebhookAttempt.create!(webhook_event: event, attempt: 1, response_status_code: 500)
        ids[:event] = event.uuid
        api :get, "/api/ccn/webhooks/#{ids[:webhook]}/events"
      }],
      ['post', '/ccn/webhooks/{id}/events/{uuid}/resend',
       -> { api :post, "/api/ccn/webhooks/#{ids[:webhook]}/events/#{ids[:event]}/resend" }],
      ['post', '/ccn/webhooks/{id}/test', -> { api :post, "/api/ccn/webhooks/#{ids[:webhook]}/test" }],
      ['delete', '/ccn/webhooks/{id}', -> { api :delete, "/api/ccn/webhooks/#{ids[:webhook]}" }],
      ['get', '/ccn/account_configs', -> { api :get, '/api/ccn/account_configs' }],
      ['put', '/ccn/account_configs/{key}',
       -> { api :put, '/api/ccn/account_configs/allow_typed_signature', { value: false } }],
      ['get', '/ccn/account_configs/{key}', -> { api :get, '/api/ccn/account_configs/allow_typed_signature' }],
      ['delete', '/ccn/account_configs/{key}',
       -> { api :delete, '/api/ccn/account_configs/allow_typed_signature' }],
      ['post', '/ccn/template_folders',
       -> { api :post, '/api/ccn/template_folders', { name: 'Contracts / Leases' } }],
      ['get', '/ccn/template_folders', -> { api :get, '/api/ccn/template_folders' }],
      ['put', '/ccn/template_folders/{id}',
       -> { api :put, "/api/ccn/template_folders/#{ids[:folder]}", { name: 'Rent' } }],
      ['delete', '/ccn/template_folders/{id}', -> { api :delete, "/api/ccn/template_folders/#{ids[:folder]}" }],
      ['post', '/ccn/templates/{id}/versions', -> { api :post, "/api/ccn/templates/#{template.id}/versions" }],
      ['get', '/ccn/templates/{id}/versions', -> { api :get, "/api/ccn/templates/#{template.id}/versions" }],
      ['get', '/ccn/templates/{id}/versions/{version_id}',
       -> { api :get, "/api/ccn/templates/#{template.id}/versions/#{ids[:version]}" }],
      ['post', '/ccn/templates/{id}/versions/{version_id}/restore',
       -> { api :post, "/api/ccn/templates/#{template.id}/versions/#{ids[:version]}/restore" }],
      ['post', '/ccn/templates/{id}/detect_fields',
       -> { api :post, "/api/ccn/templates/#{template.id}/detect_fields" }],
      ['put', '/templates/{id}',
       -> { api :put, "/api/templates/#{template.id}", { preferences: { request_email_subject: 'Signez' } } }]
    ]

    documented = operations.map { |op| [op[:method], op[:path]] }
    expect(plan.map { |method, path, _| [method, path] }).to match_array(documented)

    plan.each do |method, path, request|
      request.call

      operation = operations.find { |op| op[:method] == method && op[:path] == path }.fetch(:operation)
      schema = OpenapiContract.response_schema(operation)

      expect(response).to have_http_status(:ok),
                          "#{method.upcase} #{path}: #{response.status} #{response.body.truncate(300)}"
      expect(OpenapiContract.validate(json, schema)).to be_empty, "#{method.upcase} #{path}"

      ids[:user] ||= json['id'] if path == '/ccn/users' && method == 'post'
      ids[:webhook] ||= json['id'] if path == '/ccn/webhooks' && method == 'post'
      ids[:folder] ||= json['id'] if path == '/ccn/template_folders' && method == 'post'
      ids[:version] ||= json['id'] if path == '/ccn/templates/{id}/versions' && method == 'post'
    end
  end
end
