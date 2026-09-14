# frozen_string_literal: true

# CCN fork — Stage 2, user story 4 (specs/001-documents-by-any-route): submissions created straight from
# documents, with their own document snapshot and no template row (research D7). Gotenberg is stubbed with
# the tag fixture.
describe 'CCN submissions API (documents in)' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': user.access_token.token } }
  let(:fixtures) { Rails.root.join('spec/fixtures') }
  let(:pdf_bytes) { fixtures.join('ccn/fieldtags.pdf').binread }
  let(:pdf_base64) { Base64.strict_encode64(pdf_bytes) }
  let(:sample_bytes) { fixtures.join('sample-document.pdf').binread }
  let(:sample_base64) { Base64.strict_encode64(sample_bytes) }
  let(:gotenberg_url) { 'http://gotenberg.test:3000' }
  let(:tag_submitters) do
    [{ role: 'First Party', email: 'first@example.com' }, { role: 'Signer2', email: 'second@example.com' }]
  end
  let(:signer_field) do
    { name: 'Full name', type: 'text', role: 'Signer', areas: [{ x: 0.1, y: 0.1, w: 0.3, h: 0.05, page: 1 }] }
  end

  # Not a `let`: several examples issue more than one request and read each response.
  def json
    response.parsed_body
  end

  def api(method, path, body = {})
    public_send(method, path, headers:, params: body.to_json)
  end

  describe 'POST /api/submissions/pdf' do
    it 'creates a template-less submission carrying its own documents, schema, fields and roles' do
      api :post, '/api/submissions/pdf', name: 'Lease 12', send_email: false,
                                         documents: [{ name: 'lease', file: pdf_base64 }], submitters: tag_submitters

      expect(response).to have_http_status(:ok)
      expect(json).to include('name' => 'Lease 12', 'source' => 'api', 'status' => 'pending', 'documents' => [])
      expect(json['submitters'].pluck('role')).to eq(['First Party', 'Signer2'])
      expect(json['submitters'].pluck('email')).to eq(%w[first@example.com second@example.com])
      expect(json['schema'].pluck('name')).to eq(['lease'])
      expect(json['fields'].pluck('name')).to include('Text Field', 'FIeld2', 'Signature')

      submission = Submission.find(json['id'])

      expect(submission.template_id).to be_nil
      expect(submission.template_submitters.pluck('name')).to eq(['First Party', 'Signer2'])
      expect(submission.schema_documents.map(&:uuid)).to eq(submission.template_schema.pluck('attachment_uuid'))
      expect(submission.schema_documents.first.filename.to_s).to eq('lease.pdf')
      expect(Template.count).to eq(0)
    end

    it 'can be opened and signed through the form and yields the signed documents', sidekiq: :inline do
      api :post, '/api/submissions/pdf', send_email: false,
                                         documents: [{ name: 'contract', file: sample_base64, fields: [signer_field] }],
                                         submitters: [{ role: 'Signer', email: 'signer@example.com', name: 'Alice' }]

      expect(response).to have_http_status(:ok)

      submitter = Submitter.find(json['submitters'].first['id'])
      field_uuid = json['fields'].find { |f| f['name'] == 'Full name' }['uuid']

      get "/s/#{submitter.slug}"
      expect(response).to have_http_status(:ok)

      put "/s/#{submitter.slug}", params: { completed: 'true', values: { field_uuid => 'Alice Example' } }
      expect(response).to have_http_status(:ok)

      submitter.reload
      expect(submitter.completed_at).to be_present
      expect(submitter.documents.count).to eq(1)
      expect(submitter.submission.reload.completed_at).to be_present

      get "/api/submissions/#{submitter.submission_id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['status']).to eq('completed')
      expect(json['documents']).not_to be_empty
    end

    it 'orders the documents by position and merges them into one PDF when merge_documents is true' do
      sample_pages = Pdfium::Document.open_io(StringIO.new(sample_bytes), &:page_count)

      api :post, '/api/submissions/pdf', send_email: false, merge_documents: true,
                                         documents: [{ name: 'contract', file: sample_base64, position: 1 },
                                                     { name: 'lease', file: pdf_base64, position: 0 }],
                                         submitters: tag_submitters

      expect(response).to have_http_status(:ok)
      expect(json['schema'].size).to eq(1)
      expect(json['fields'].flat_map { |f| f['areas'].pluck('page') }.max).to be < 2 # lease came first

      submission = Submission.find(json['id'])

      expect(submission.documents.count).to eq(1)
      expect(submission.documents.first.metadata.dig('pdf', 'number_of_pages')).to eq(2 + sample_pages)
      expect(Template.count).to eq(0)
    end

    it 'enqueues the first invitation only when send_email is true' do
      body = { documents: [{ name: 'lease', file: pdf_base64 }], submitters: tag_submitters }

      expect { api :post, '/api/submissions/pdf', body.merge(send_email: false) }
        .not_to change(SendSubmitterInvitationEmailJob.jobs, :size)
      expect { api :post, '/api/submissions/pdf', body.merge(send_email: true) }
        .to change(SendSubmitterInvitationEmailJob.jobs, :size).by(1)
    end

    it 'answers 422 for template_ids, variables, an unknown role and fieldless documents, leaving nothing behind' do
      documents = [{ name: 'lease', file: pdf_base64 }]

      api :post, '/api/submissions/pdf', template_ids: [1], documents:, submitters: tag_submitters
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_not_supported_yet', feature: 'template_ids'))

      api :post, '/api/submissions/pdf', variables: { a: 1 }, documents:, submitters: tag_submitters
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_not_supported_yet', feature: 'variables'))

      api :post, '/api/submissions/pdf', documents:, submitters: [{ role: 'Nobody', email: 'x@example.com' }]
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to be_present

      api :post, '/api/submissions/pdf', documents: [{ name: 'plain', file: sample_base64 }], submitters: tag_submitters
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to match(/no fields/)

      expect(Template.count).to eq(0)
      expect(Submission.count).to eq(0)
    end
  end

  describe 'POST /api/submissions/docx' do
    it 'converts through the sidecar and creates the submission' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert")
        .to_return(status: 200, body: pdf_bytes, headers: { 'Content-Type' => 'application/pdf' })
      docx = Base64.strict_encode64(fixtures.join('fieldtags.docx').binread)

      api :post, '/api/submissions/docx', send_email: false, documents: [{ name: 'fieldtags', file: docx }],
                                          submitters: tag_submitters

      expect(response).to have_http_status(:ok)
      expect(json['schema'].pluck('name')).to eq(['fieldtags'])
      expect(Submission.find(json['id']).template_id).to be_nil
    end
  end

  describe 'POST /api/submissions/html' do
    it 'renders the html through the sidecar and creates the submission' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      stub = stub_request(:post, "#{gotenberg_url}/forms/chromium/convert/html")
             .with { |req| req.body.include?('{{Name;type=text;role=First Party') }
             .to_return(status: 200, body: pdf_bytes, headers: { 'Content-Type' => 'application/pdf' })
      html = '<p><text-field name="Name" role="First Party"></text-field></p>'

      api :post, '/api/submissions/html', send_email: false, documents: [{ name: 'web', html: }],
                                          submitters: tag_submitters

      expect(response).to have_http_status(:ok)
      expect(stub).to have_been_requested
      expect(json['schema'].pluck('name')).to eq(['web'])
      expect(Template.count).to eq(0)
    end
  end
end
