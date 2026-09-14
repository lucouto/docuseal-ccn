# frozen_string_literal: true

# CCN fork — Stage 2, user stories 1 and 2 (specs/001-documents-by-any-route): text tags and Word documents
# through the builder's own upload endpoints.
describe 'CCN document upload (builder)' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:fixtures) { Rails.root.join('spec/fixtures') }
  let(:pdf_bytes) { fixtures.join('ccn/fieldtags.pdf').binread }
  let(:docx_type) { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }
  let(:pdf_upload) { Rack::Test::UploadedFile.new(fixtures.join('ccn/fieldtags.pdf'), 'application/pdf') }
  let(:docx_upload) { Rack::Test::UploadedFile.new(fixtures.join('fieldtags.docx'), docx_type) }
  let(:gotenberg_url) { 'http://gotenberg.test:3000' }
  let(:expected_names) { ['Text Field', 'Field1', 'FIeld2', 'DOB', 'Signature', 'Sign here', 'Name', 'Test'] }
  let(:json_headers) { { 'Accept' => 'application/json' } }

  before { sign_in(user) }

  def page_texts(attachment)
    Pdfium::Document.open_io(StringIO.new(attachment.download)) do |doc|
      Array.new(doc.page_count) { |i| doc.get_page(i).text_nodes.map(&:content).join }
    end
  end

  describe 'PDF with text tags' do
    it 'creates the fields, the signer roles and erases the tags from the stored document' do
      post '/templates_upload', params: { files: [pdf_upload] }

      template = Template.last

      expect(response).to redirect_to(edit_template_path(template))
      expect(template.fields.pluck('name')).to match_array(expected_names)
      expect(template.submitters.pluck('name')).to eq(['First Party', 'Signer2'])

      first_party, signer2 = template.submitters.pluck('uuid')
      by_name = template.fields.index_by { |f| f['name'] }

      expect(by_name['FIeld2']['submitter_uuid']).to eq(signer2)
      expect(by_name['Test']['submitter_uuid']).to eq(signer2)
      expect(by_name['Text Field']['submitter_uuid']).to eq(first_party)
      expect(by_name['Text Field']['areas'].pluck('page')).to eq([0, 1])
      expect(by_name['Name']).to include('readonly' => true, 'default_value' => 'Bob')

      document = template.schema_documents.first
      texts = page_texts(document)

      # The fixture keeps a deliberate unclosed '{{' on page 2, so only complete tags must be gone. Redacted
      # lines lose their spaces in extracted text (upstream Page#redact rebuilds glyph by glyph).
      expect(texts.join).not_to match(Templates::FindTextTagFields::TAG_REGEXP)
      expect(texts.first.delete(' ')).to include('Tenantname:')
      expect(document.metadata.dig('pdf', 'number_of_pages')).to eq(2)
      expect(document.preview_images.count).to eq(2)
    end

    it 'keeps the tag text when remove_tags is false' do
      post '/templates_upload', params: { files: [pdf_upload], remove_tags: 'false' }

      template = Template.last

      expect(template.fields.size).to eq(8)
      expect(page_texts(template.schema_documents.first).join).to include('{{DOB;type=date}}')
    end

    it 'decrypts a password-protected PDF, erases its tags and stores it without the password' do
      encrypted = Rack::Test::UploadedFile.new(fixtures.join('ccn/fieldtags-encrypted.pdf'), 'application/pdf')

      post '/templates_upload', params: { files: [encrypted], password: 'secret' }

      template = Template.last
      document = template.schema_documents.first

      expect(template.fields.pluck('name')).to match_array(expected_names)
      expect(page_texts(document).join).not_to match(Templates::FindTextTagFields::TAG_REGEXP)
      expect(Pdfium::Document.open_io(StringIO.new(document.download), &:encrypted?)).to be(false)
    end

    it 'persists and returns the roles added by tags when a document is added to an existing template' do
      template = create(:template, account:, author: user)

      post "/templates/#{template.id}/documents", params: { files: [pdf_upload] }, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['submitters'].pluck('name')).to eq(['First Party', 'Signer2'])
      expect(template.reload.submitters.pluck('name')).to eq(['First Party', 'Signer2'])

      fields = response.parsed_body['documents'].first.dig('metadata', 'pdf', 'fields')
      signer2 = template.submitters.last['uuid']

      expect(fields.find { |f| f['name'] == 'FIeld2' }['submitter_uuid']).to eq(signer2)
      expect(fields.find { |f| f['name'] == 'Text Field' }['submitter_uuid']).to eq(template.submitters.first['uuid'])
    end

    it 'leaves a document without tags on the upstream path' do
      plain = Rack::Test::UploadedFile.new(fixtures.join('sample-document.pdf'), 'application/pdf')

      post '/templates_upload', params: { files: [plain] }

      expect(Template.last.fields).to eq([])
      expect(Template.last.submitters.size).to eq(1)
    end
  end

  describe 'Word document' do
    before { stub_const('Ccn::GOTENBERG_URL', gotenberg_url) }

    it 'is converted by the sidecar and yields the same fields as the PDF' do
      stub = stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert")
             .with { |req| req.body.include?('filename="fieldtags.docx"') }
             .to_return(status: 200, body: pdf_bytes, headers: { 'Content-Type' => 'application/pdf' })

      post '/templates_upload', params: { files: [docx_upload] }

      template = Template.last
      document = template.schema_documents.first

      expect(stub).to have_been_requested
      expect(template.name).to eq('fieldtags')
      expect(template.fields.pluck('name')).to match_array(expected_names)
      expect(document.filename.to_s).to eq('fieldtags.pdf')
      expect(document.content_type).to eq('application/pdf')
      expect(page_texts(document).join).not_to match(Templates::FindTextTagFields::TAG_REGEXP)
    end

    it 'redirects the main upload with the translated message and no partial template when the sidecar is down' do
      stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert").to_raise(Errno::ECONNREFUSED)

      expect { post '/templates_upload', params: { files: [docx_upload] } }.not_to change(Template, :count)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t('ccn_conversion_unavailable'))
    end

    it 'answers the builder JSON endpoint with a clear error when the sidecar is unreachable' do
      stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert").to_raise(Errno::ECONNREFUSED)
      template = create(:template, account:, author: user)

      post "/templates/#{template.id}/documents", params: { files: [docx_upload] }, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_conversion_unavailable'))
      expect(template.reload.schema_documents.count).to eq(1)
    end

    it 'reports a timeout and a rejection distinctly' do
      template = create(:template, account:, author: user)

      stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert").to_timeout
      post "/templates/#{template.id}/documents", params: { files: [docx_upload] }, headers: json_headers
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_conversion_timeout'))

      stub_request(:post, "#{gotenberg_url}/forms/libreoffice/convert").to_return(status: 400, body: 'bad')
      post "/templates/#{template.id}/documents", params: { files: [docx_upload] }, headers: json_headers
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_conversion_rejected', status: 400))
    end

    it 'is refused as before when no sidecar is configured' do
      stub_const('Ccn::GOTENBERG_URL', nil)
      template = create(:template, account:, author: user)

      expect { post "/templates/#{template.id}/documents", params: { files: [docx_upload] } }
        .to raise_error(Templates::CreateAttachments::InvalidFileType)
    end
  end

  describe 'advanced formats switch' do
    it 'accepts office extensions in the upload input only when a sidecar is configured' do
      stub_const('Ccn::GOTENBERG_URL', gotenberg_url)
      get '/'
      expect(response.body).to include('.docx')

      stub_const('Ccn::GOTENBERG_URL', nil)
      get '/'
      expect(response.body).not_to include('.docx')
    end
  end
end
