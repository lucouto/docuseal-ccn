# frozen_string_literal: true

# CCN fork — Stage 2, user story 3 (specs/001-documents-by-any-route): the five template ingestion operations
# upstream reserves for Pro. Gotenberg is stubbed (no LibreOffice/Chromium in CI); the stub answers with the
# tag fixture so the pipeline after conversion is exercised for real.
describe 'CCN templates API (documents in)' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': user.access_token.token } }
  let(:fixtures) { Rails.root.join('spec/fixtures') }
  let(:pdf_bytes) { fixtures.join('ccn/fieldtags.pdf').binread }
  let(:pdf_base64) { Base64.strict_encode64(pdf_bytes) }
  let(:sample_base64) { Base64.strict_encode64(fixtures.join('sample-document.pdf').binread) }
  let(:gotenberg_url) { 'http://gotenberg.test:3000' }
  let(:tag_names) { ['Text Field', 'Field1', 'FIeld2', 'DOB', 'Signature', 'Sign here', 'Name', 'Test'] }
  let(:json) { response.parsed_body }

  def api(method, path, body = {})
    public_send(method, path, headers:, params: body.to_json)
  end

  def page_texts(attachment)
    Pdfium::Document.open_io(StringIO.new(attachment.download)) do |doc|
      Array.new(doc.page_count) { |i| doc.get_page(i).text_nodes.map(&:content).join }
    end
  end

  def area_uuids(fields)
    fields.flat_map { |f| Array.wrap(f['areas']).pluck('attachment_uuid') }.uniq
  end

  describe 'POST /api/templates/pdf' do
    it 'creates a template with detected and explicit fields, roles, folder and documents' do
      api :post, '/api/templates/pdf',
          name: 'Lease', folder_name: 'Leases', external_id: 'lease-1',
          documents: [{ name: 'lease', file: pdf_base64,
                        fields: [{ name: 'Rent', type: 'number', role: 'Tenant',
                                   areas: [{ x: 0.1, y: 0.2, w: 0.3, h: 0.05, page: 2 }] }] }]

      expect(response).to have_http_status(:ok)
      expect(json).to include('name' => 'Lease', 'folder_name' => 'Leases', 'external_id' => 'lease-1',
                              'source' => 'api')
      expect(json['documents'].size).to eq(1)
      expect(json['documents'].first).to include('filename' => 'lease.pdf')
      expect(json['documents'].first['url']).to be_present
      expect(json['fields'].pluck('name')).to match_array(tag_names + ['Rent'])
      expect(json['submitters'].pluck('name')).to eq(['First Party', 'Signer2', 'Tenant'])

      rent = json['fields'].find { |f| f['name'] == 'Rent' }
      tenant = json['submitters'].find { |s| s['name'] == 'Tenant' }

      expect(rent['areas'].first).to include('page' => 1, 'attachment_uuid' => json['schema'].first['attachment_uuid'])
      expect(rent['submitter_uuid']).to eq(tenant['uuid'])

      template = Template.find(json['id'])

      expect(template.author).to eq(user)
      expect(page_texts(template.schema_documents.first).join).not_to match(Templates::FindTextTagFields::TAG_REGEXP)
    end

    it 'lets an explicit field override a detected field with the same name' do
      api :post, '/api/templates/pdf', documents: [{ name: 'lease', file: pdf_base64, fields: [{ name: 'DOB' }] }]

      dob = json['fields'].select { |f| f['name'] == 'DOB' }

      expect(dob.size).to eq(1)
      expect(dob.first['type']).to eq('text')
    end

    it 'upserts on external_id: the same template receives the new document and name, fields follow' do
      api :post, '/api/templates/pdf', name: 'v1', external_id: 'lease-2', documents: [{ name: 'a', file: pdf_base64 }]

      first_id = json['id']
      first_uuid = json['schema'].first['attachment_uuid']

      expect do
        api :post, '/api/templates/pdf', name: 'v2', external_id: 'lease-2',
                                         documents: [{ name: 'b', file: sample_base64 }]
      end.not_to change(Template, :count)

      expect(json['id']).to eq(first_id)
      expect(json['name']).to eq('v2')
      expect(json['schema'].pluck('name')).to eq(['b'])
      expect(json['schema'].first['attachment_uuid']).not_to eq(first_uuid)
      expect(json['fields'].pluck('name')).to match_array(tag_names)
      expect(area_uuids(json['fields'])).to eq([json['schema'].first['attachment_uuid']])
    end

    it 'keeps the tag text when remove_tags is false' do
      api :post, '/api/templates/pdf', remove_tags: false, documents: [{ name: 'lease', file: pdf_base64 }]

      expect(page_texts(Template.last.schema_documents.first).join).to include('{{DOB;type=date}}')
    end

    it 'downloads an https document and names it after the URL' do
      stub_request(:get, 'https://files.example.com/docs/lease+v2.pdf')
        .to_return(body: pdf_bytes, headers: { 'Content-Type' => 'application/pdf' })

      api :post, '/api/templates/pdf', documents: [{ file: 'https://files.example.com/docs/lease+v2.pdf' }]

      expect(response).to have_http_status(:ok)
      expect(json['documents'].first['filename']).to eq('lease+v2.pdf')
      expect(json['name']).to eq('lease+v2')
    end

    it 'flattens PDF form fields on request while still detecting them' do
      acroform = Base64.strict_encode64(fixtures.join('ccn/acroform.pdf').binread)

      api :post, '/api/templates/pdf', flatten: true, documents: [{ name: 'form', file: acroform }]

      expect(response).to have_http_status(:ok)
      expect(json['fields'].pluck('type')).to include('signature')

      stored = Template.last.schema_documents.first
      data = stored.download

      Pdfium::Document.open_io(StringIO.new(data)) do |doc|
        expect(Templates::FindPdfiumAcroFields.call(stored, doc, data)).to be_empty
      end
    end

    it 'answers every client error with a 422 and leaves no template behind' do
      api :post, '/api/templates/pdf', documents: [{ name: 'x', file: '%%%' }]
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to match(/base64/)

      api :post, '/api/templates/pdf', documents: [{ file: 'http://files.example.com/x.pdf' }]
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to match(/HTTPS/)

      api :post, '/api/templates/pdf', name: 'none'
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to match(/documents/)

      encrypted = Base64.strict_encode64(fixtures.join('ccn/fieldtags-encrypted.pdf').binread)
      api :post, '/api/templates/pdf', documents: [{ name: 'locked', file: encrypted }]
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_pdf_encrypted'))

      api :post, '/api/templates/pdf', documents: [{ name: 'x', file: Base64.strict_encode64('plain text') }]
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_unsupported_file_type', type: 'text/plain'))

      expect(Template.count).to eq(0)
    end
  end

  describe 'POST /api/templates/docx' do
    let(:docx_base64) { Base64.strict_encode64(fixtures.join('fieldtags.docx').binread) }

    it 'converts through the sidecar and yields the tag fields' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      stub = stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert")
             .with { |req| req.body.include?('filename="fieldtags.docx"') }
             .to_return(status: 200, body: pdf_bytes, headers: { 'Content-Type' => 'application/pdf' })

      api :post, '/api/templates/docx', documents: [{ name: 'fieldtags', file: docx_base64 }]

      expect(response).to have_http_status(:ok)
      expect(stub).to have_been_requested
      expect(json['fields'].pluck('name')).to match_array(tag_names)
      expect(json['documents'].first['filename']).to eq('fieldtags.pdf')
    end

    it 'answers 422 when no sidecar is configured' do
      stub_const('Ccn::GOTENBERG_URL', nil)

      api :post, '/api/templates/docx', documents: [{ name: 'fieldtags', file: docx_base64 }]

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_conversion_unavailable'))
    end

    it 'answers 422 for dynamic documents (not supported yet)' do
      api :post, '/api/templates/docx', documents: [{ name: 'fieldtags', file: docx_base64, dynamic: true }]

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_not_supported_yet', feature: 'dynamic documents'))
    end
  end

  describe 'POST /api/templates/html' do
    before { stub_const('Ccn::GOTENBERG_URL', gotenberg_url) }

    it 'rewrites field elements into markers, renders on the requested size and detects the fields' do
      stub = stub_request(:post, "#{gotenberg_url}/forms/chromium/convert/html").with do |req|
        req.body.include?('{{Tenant;type=text;role=Tenant;required=false;width=150.0;height=18.0}}') &&
          req.body.include?('name="paperWidth"') && req.body.include?('8.27') &&
          req.body.include?('filename="header.html"')
      end.to_return(status: 200, body: pdf_bytes, headers: { 'Content-Type' => 'application/pdf' })

      html = '<p>Tenant: <text-field name="Tenant" role="Tenant" required="false" ' \
             'style="width:200px;height:24px"></text-field></p>'

      api :post, '/api/templates/html', html:, name: 'Web lease', size: 'A4', html_header: '<p>Head</p>'

      expect(response).to have_http_status(:ok)
      expect(stub).to have_been_requested
      expect(json['name']).to eq('Web lease')
      expect(json['documents'].first['filename']).to eq('Web lease.pdf')
      expect(json['fields'].pluck('name')).to match_array(tag_names) # the stubbed sidecar returns the tag fixture
    end

    it 'rejects an unknown page size and a missing html' do
      api :post, '/api/templates/html', html: '<p>x</p>', size: 'B5'
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to match(/size/)

      api :post, '/api/templates/html', name: 'empty'
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to match(/html/)
    end
  end

  describe 'POST /api/templates/merge' do
    let(:first) { create(:template, account:, author: user).reload }
    let(:second) { create(:template, account:, author: user, submitter_count: 2).reload }

    it 'clones both documents into a new template, maps roles positionally and leaves the sources untouched' do
      before_schema = [first.schema, second.schema]

      api :post, '/api/templates/merge', template_ids: [first.id, second.id], name: 'Merged', roles: %w[Buyer Seller]

      expect(response).to have_http_status(:ok)
      expect(json['name']).to eq('Merged')
      expect(json['schema'].size).to eq(2)
      expect(json['documents'].size).to eq(2)
      expect(json['submitters'].pluck('name')).to eq(%w[Buyer Seller])

      buyer, seller = json['submitters'].pluck('uuid')

      expect(json['fields'].size).to eq(first.fields.size + second.fields.size)
      expect(json['fields'].pluck('submitter_uuid').uniq).to contain_exactly(buyer, seller)
      expect(area_uuids(json['fields'])).to match_array(json['schema'].pluck('attachment_uuid'))
      expect(json['fields'].pluck('uuid')).not_to include(*first.fields.pluck('uuid'))

      expect([first.reload.schema, second.reload.schema]).to eq(before_schema)
      expect(Template.find(json['id']).schema_documents.count).to eq(2)
    end

    it 'matches roles by name when none are given' do
      api :post, '/api/templates/merge', template_ids: [first.id, second.id]

      expect(response).to have_http_status(:ok)
      expect(json['name']).to eq("#{first.name} (Merged)")
      expect(json['submitters'].pluck('name')).to eq(['First Party', 'Second Party'])
    end

    it 'answers 422 for an archived template id' do
      second.update!(archived_at: Time.current)

      api :post, '/api/templates/merge', template_ids: [first.id, second.id]

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_template_not_found', id: second.id))
    end
  end

  describe 'PUT /api/templates/:id/documents' do
    let(:template) { create(:template, account:, author: user).reload }

    it 'adds, replaces and removes documents, moving fields accordingly' do
      original_uuid = template.schema.first['attachment_uuid']
      original_fields = template.fields.pluck('uuid')

      api :put, "/api/templates/#{template.id}/documents", documents: [{ name: 'tags', file: pdf_base64, position: 0 }]
      expect(response).to have_http_status(:ok)
      expect(json['schema'].pluck('name')).to eq(['tags', 'sample-document'])
      expect(json['fields'].pluck('name')).to include(*tag_names)
      expect(json['submitters'].pluck('name')).to eq(['First Party', 'Signer2'])

      api :put, "/api/templates/#{template.id}/documents",
          documents: [{ name: 'sample-document', file: sample_base64, position: 1, replace: true }]
      replaced_uuid = json['schema'].last['attachment_uuid']
      moved = json['fields'].select { |f| original_fields.include?(f['uuid']) }
      expect(json['schema'].size).to eq(2)
      expect(replaced_uuid).not_to eq(original_uuid)
      expect(moved.size).to eq(original_fields.size)
      expect(area_uuids(moved)).to eq([replaced_uuid])

      api :put, "/api/templates/#{template.id}/documents", documents: [{ position: 0, remove: true }]
      expect(json['schema'].pluck('name')).to eq(['sample-document'])
      expect(json['fields'].pluck('name')).not_to include(*tag_names)
      expect(json['fields'].pluck('uuid')).to match_array(original_fields)
    end

    it 'adds a document rendered from html' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      stub_request(:post, "#{gotenberg_url}/forms/chromium/convert/html")
        .to_return(status: 200, body: pdf_bytes, headers: { 'Content-Type' => 'application/pdf' })

      api :put, "/api/templates/#{template.id}/documents", documents: [{ name: 'web', html: '<p>Hi</p>' }]

      expect(response).to have_http_status(:ok)
      expect(json['schema'].pluck('name')).to eq(%w[sample-document web])
    end

    it 'merges all documents into one PDF with fields re-pointed and pages offset' do
      two = create(:template, account:, author: user, attachment_count: 2).reload
      documents = two.schema_documents.index_by(&:uuid)
      first_pages = documents[two.schema.first['attachment_uuid']].metadata.dig('pdf', 'number_of_pages').to_i
      total_pages = documents.values.sum { |d| d.metadata.dig('pdf', 'number_of_pages').to_i }
      second_uuid = two.schema.last['attachment_uuid']
      second_fields = two.fields.select { |f| f['areas'].any? { |a| a['attachment_uuid'] == second_uuid } }
                        .pluck('uuid')

      api :put, "/api/templates/#{two.id}/documents", merge: true

      expect(response).to have_http_status(:ok)
      expect(first_pages).to be_positive
      expect(json['schema'].size).to eq(1)

      merged_uuid = json['schema'].first['attachment_uuid']
      offset_pages = json['fields'].select { |f| second_fields.include?(f['uuid']) }
                                   .flat_map { |f| f['areas'].pluck('page') }

      expect(area_uuids(json['fields'])).to eq([merged_uuid])
      expect(offset_pages).to all(be >= first_pages)
      merged_document = Template.find(two.id).schema_documents.first
      expect(merged_document.metadata.dig('pdf', 'number_of_pages')).to eq(total_pages)
    end

    it 'answers 422 when asked to remove a document that does not exist' do
      api :put, "/api/templates/#{template.id}/documents", documents: [{ position: 7, remove: true }]

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to match(/remove/)
    end
  end

  it 'routes the ingestion paths instead of answering the Pro 404' do
    expect(ErrorsController.constants).not_to include(:ENTERPRISE_PATHS, :ENTERPRISE_FEATURE_MESSAGE)
    expect(Rails.application.routes.recognize_path('/api/templates/pdf', method: :post))
      .to include(controller: 'api/ccn_templates_documents', action: 'pdf')
  end
end
