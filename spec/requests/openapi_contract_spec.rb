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
  let(:pending_operations) do
    [
      %w[post /templates/pdf],
      %w[post /templates/docx],
      %w[post /templates/html],
      %w[post /templates/merge],
      %w[put /templates/{id}/documents],
      %w[post /submissions/pdf],
      %w[post /submissions/docx],
      %w[post /submissions/html]
    ]
  end

  # Where upstream's own 3.2.4 API disagrees with its published spec. Pinned explicitly so a fork change
  # that fixes or worsens a discrepancy is noticed; re-check on every upstream rebase.
  #   - GET /submissions/{id}: the spec requires "metadata", Submissions::SerializeForApi never emits it.
  #   - submission "name" is typed string but is null for unnamed submissions (fixtures below set a name).
  let(:known_upstream_deviations) do
    {
      %w[get /submissions/{id}] => ['$: missing required key "metadata"']
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
