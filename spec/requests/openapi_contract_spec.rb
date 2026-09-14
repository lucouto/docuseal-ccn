# frozen_string_literal: true

# CCN fork — contract test against upstream's docs/openapi.json (FORK-PLAN.md §6, gate S0/S2).
#
# Part 1 pins the gap between the published API and this build: every operation of the spec
# must be routable, except the ones listed in PENDING. Implementing one of them without
# removing it from PENDING fails the test, and so does a regression that removes a route.
# Part 2 exercises each implemented operation for real and checks the response against the
# spec's declared response schema.
describe 'OpenAPI contract' do
  # Pro-only in upstream 3.2.4 — implemented by the CCN fork in Stage 2 (FORK-PLAN.md §3.1).
  let(:pending_operations) { [] }

  # Where upstream's own 3.2.4 API disagrees with its published spec. Pinned explicitly so a fork change
  # that fixes or worsens a discrepancy is noticed; re-check on every upstream rebase.
  #   - GET /submissions/{id}: the spec requires "metadata", Submissions::SerializeForApi never emits it.
  #   - submission "name" is typed string but is null for unnamed submissions (fixtures below set a name).
  #   - POST /submissions/{pdf,docx,html}: "expire_at" is typed string (not nullable) but a submission without
  #     an expiry has null there, in Submissions::SerializeForApi as in every other submission response.
  let(:known_upstream_deviations) do
    expire_at = ['$.expire_at: expected string, got null nil']

    {
      %w[get /submissions/{id}] => ['$: missing required key "metadata"'],
      %w[post /submissions/pdf] => expire_at,
      %w[post /submissions/docx] => expire_at,
      %w[post /submissions/html] => expire_at
    }
  end

  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': author.access_token.token } }
  let(:template) { create(:template, account:, author:, only_field_types: %w[text signature]) }
  let(:submission) do
    create(:submission, :with_submitters, template:, created_by_user: author, name: 'Contract submission')
  end
  let(:submitter) { submission.submitters.first }
  let(:fieldtags_base64) { Base64.strict_encode64(Rails.root.join('spec/fixtures/ccn/fieldtags.pdf').binread) }
  let(:gotenberg_url) { 'http://gotenberg.test:3000' }

  def expect_conforming_response(method, path, status: 200)
    operation = OpenapiContract.operations.find { |op| op[:method] == method && op[:path] == path }
    schema = OpenapiContract.response_schema(operation.fetch(:operation), status)

    expect(response).to have_http_status(status)
    expect(schema).to be_present, "docs/openapi.json declares no #{status} JSON schema for #{method.upcase} #{path}"
    expect(OpenapiContract.validate(response.parsed_body, schema))
      .to match_array(known_upstream_deviations.fetch([method, path], []))
  end

  describe 'coverage of docs/openapi.json' do
    it 'routes every documented operation except the known pending ones' do
      unrouted = OpenapiContract.operations
                                .reject { |op| OpenapiContract.routable?(op[:method], op[:path]) }
                                .map { |op| [op[:method], op[:path]] }

      expect(unrouted).to match_array(pending_operations)
    end

    it 'documents at least the 22 operations known at fork time' do
      expect(OpenapiContract.operations.size).to be >= 22
    end
  end

  describe 'templates' do
    it 'GET /templates' do
      template

      get '/api/templates', headers: headers

      expect_conforming_response('get', '/templates')
    end

    it 'GET /templates/{id}' do
      get "/api/templates/#{template.id}", headers: headers

      expect_conforming_response('get', '/templates/{id}')
    end

    it 'PUT /templates/{id}' do
      put "/api/templates/#{template.id}", headers: headers, params: { name: 'Contract test' }.to_json

      expect_conforming_response('put', '/templates/{id}')
    end

    it 'POST /templates/{id}/clone' do
      post "/api/templates/#{template.id}/clone", headers: headers, params: { name: 'Contract clone' }.to_json

      expect_conforming_response('post', '/templates/{id}/clone')
    end

    it 'DELETE /templates/{id}' do
      delete "/api/templates/#{template.id}", headers: headers

      expect_conforming_response('delete', '/templates/{id}')
    end

    # CCN fork, Stage 2: the operations upstream reserves for Pro (Gotenberg stubbed with the tag fixture).
    it 'POST /templates/pdf' do
      body = { name: 'Contract pdf', documents: [{ name: 'tags', file: fieldtags_base64 }] }

      post '/api/templates/pdf', headers: headers, params: body.to_json

      expect_conforming_response('post', '/templates/pdf')
    end

    it 'POST /templates/docx' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert")
        .to_return(status: 200, body: Base64.strict_decode64(fieldtags_base64))
      docx = Base64.strict_encode64(Rails.root.join('spec/fixtures/fieldtags.docx').binread)

      body = { name: 'Contract docx', documents: [{ name: 'tags', file: docx }] }

      post '/api/templates/docx', headers: headers, params: body.to_json

      expect_conforming_response('post', '/templates/docx')
    end

    it 'POST /templates/html' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      stub_request(:post, "#{gotenberg_url}/forms/chromium/convert/html")
        .to_return(status: 200, body: Base64.strict_decode64(fieldtags_base64))

      body = { name: 'Contract html', html: '<p><text-field name="A"></text-field></p>' }

      post '/api/templates/html', headers: headers, params: body.to_json

      expect_conforming_response('post', '/templates/html')
    end

    it 'POST /templates/merge' do
      other = create(:template, account:, author:)

      body = { name: 'Contract merge', template_ids: [template.id, other.id] }

      post '/api/templates/merge', headers: headers, params: body.to_json

      expect_conforming_response('post', '/templates/merge')
    end

    it 'PUT /templates/{id}/documents' do
      body = { documents: [{ name: 'tags', file: fieldtags_base64 }] }

      put "/api/templates/#{template.id}/documents", headers: headers, params: body.to_json

      expect_conforming_response('put', '/templates/{id}/documents')
    end
  end

  describe 'submissions' do
    it 'GET /submissions' do
      submission

      get '/api/submissions', headers: headers

      expect_conforming_response('get', '/submissions')
    end

    it 'POST /submissions' do
      post '/api/submissions', headers: headers, params: {
        template_id: template.id,
        send_email: false,
        submitters: [{ role: 'First Party', email: 'contract.test@example.com' }]
      }.to_json

      expect_conforming_response('post', '/submissions')
    end

    it 'GET /submissions/{id}' do
      get "/api/submissions/#{submission.id}", headers: headers

      expect_conforming_response('get', '/submissions/{id}')
    end

    it 'GET /submissions/{id}/documents' do
      get "/api/submissions/#{submission.id}/documents", headers: headers

      expect_conforming_response('get', '/submissions/{id}/documents')
    end

    it 'POST /submissions/emails' do
      post '/api/submissions/emails', headers: headers, params: {
        template_id: template.id,
        send_email: false,
        emails: 'first.contract@example.com, second.contract@example.com'
      }.to_json

      expect_conforming_response('post', '/submissions/emails')
    end

    it 'DELETE /submissions/{id}' do
      delete "/api/submissions/#{submission.id}", headers: headers

      expect_conforming_response('delete', '/submissions/{id}')
    end

    # CCN fork, Stage 2: submissions from documents (Gotenberg stubbed with the tag fixture).
    it 'POST /submissions/pdf' do
      body = { send_email: false, documents: [{ name: 'tags', file: fieldtags_base64 }],
               submitters: [{ role: 'First Party', email: 'contract.pdf@example.com' }] }

      post '/api/submissions/pdf', headers: headers, params: body.to_json

      expect_conforming_response('post', '/submissions/pdf')
    end

    it 'POST /submissions/docx' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert")
        .to_return(status: 200, body: Base64.strict_decode64(fieldtags_base64))
      docx = Base64.strict_encode64(Rails.root.join('spec/fixtures/fieldtags.docx').binread)
      body = { send_email: false, documents: [{ name: 'tags', file: docx }],
               submitters: [{ role: 'First Party', email: 'contract.docx@example.com' }] }

      post '/api/submissions/docx', headers: headers, params: body.to_json

      expect_conforming_response('post', '/submissions/docx')
    end

    it 'POST /submissions/html' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      stub_request(:post, "#{gotenberg_url}/forms/chromium/convert/html")
        .to_return(status: 200, body: Base64.strict_decode64(fieldtags_base64))
      body = { send_email: false, documents: [{ name: 'web', html: '<p><text-field name="A"></text-field></p>' }],
               submitters: [{ role: 'First Party', email: 'contract.html@example.com' }] }

      post '/api/submissions/html', headers: headers, params: body.to_json

      expect_conforming_response('post', '/submissions/html')
    end
  end

  describe 'submitters' do
    it 'GET /submitters' do
      submitter

      get '/api/submitters', headers: headers

      expect_conforming_response('get', '/submitters')
    end

    it 'GET /submitters/{id}' do
      get "/api/submitters/#{submitter.id}", headers: headers

      expect_conforming_response('get', '/submitters/{id}')
    end

    it 'PUT /submitters/{id}' do
      put "/api/submitters/#{submitter.id}", headers: headers, params: { name: 'Contract Submitter' }.to_json

      expect_conforming_response('put', '/submitters/{id}')
    end
  end
end
