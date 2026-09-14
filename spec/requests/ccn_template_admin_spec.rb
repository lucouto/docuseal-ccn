# frozen_string_literal: true

# CCN fork — Stage 3, user story 4 (specs/002-everything-by-api): templates fully configurable by API —
# preferences on PUT /api/templates/{id}, folders, versions with restore, field detection.
describe 'CCN template administration API' do
  let(:account) { create(:account, timezone: 'Europe/Paris') }
  let(:admin) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': admin.access_token.token, 'Content-Type': 'application/json' } }
  let(:template) { create(:template, account:, author: admin) }

  def json
    response.parsed_body
  end

  def api(method, path, body = nil)
    public_send(method, path, headers:, params: body&.to_json)
  end

  describe 'PUT /api/templates/{id} with preferences' do
    it 'stores the UI preference keys with their coercions, removes on null and keeps the upstream response' do
      api :put, "/api/templates/#{template.id}",
          { name: 'Renamed', preferences: { request_email_subject: 'Merci de signer {{template.name}}',
                                            require_email_2fa: 'true', completed_redirect_url: 'https://x.org',
                                            completed_message: { title: 'Done', body: '' },
                                            default_expire_at: '2027-01-15 10:00' } }

      expect(response).to have_http_status(:ok)
      expect(json.keys).to contain_exactly('id', 'updated_at')

      api :get, "/api/templates/#{template.id}"
      expect(json['name']).to eq('Renamed')
      expect(json['preferences']).to include('request_email_subject' => 'Merci de signer {{template.name}}',
                                             'require_email_2fa' => true, 'completed_redirect_url' => 'https://x.org',
                                             'completed_message' => { 'title' => 'Done' })
      expect(json['preferences']['default_expire_at']).to start_with('2027-01-15T09:00:00') # Paris → UTC

      api :put, "/api/templates/#{template.id}", { template: { preferences: { completed_redirect_url: nil } } }
      expect(response).to have_http_status(:ok)
      expect(template.reload.preferences).not_to have_key('completed_redirect_url')
      expect(template.preferences['request_email_subject']).to eq('Merci de signer {{template.name}}')
    end

    it 'refuses an unknown preference key without changing anything' do
      api :put, "/api/templates/#{template.id}", { preferences: { colour: 'red' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_unknown_preference', key: 'colour'))
      expect(template.reload.preferences).to eq({})
    end
  end

  describe '/api/ccn/template_folders' do
    it 'creates two-level folders, lists them with counts, renames and archives empty ones' do
      api :post, '/api/ccn/template_folders', { name: 'S3 gate / Sub' }
      expect(response).to have_http_status(:ok)
      expect(json).to include('name' => 'Sub', 'full_name' => 'S3 gate / Sub', 'templates_count' => 0)
      expect(json['parent_folder_id']).to be_present
      sub_id = json['id']

      api :post, '/api/ccn/template_folders', { name: 'S3 gate / Sub' }
      expect(json['id']).to eq(sub_id) # found, not duplicated

      api :post, '/api/ccn/template_folders', { name: 'A / B / C' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_folder_depth'))

      api :post, '/api/ccn/template_folders', { name: '' }
      expect(response).to have_http_status(:unprocessable_content)

      api :put, "/api/templates/#{template.id}", { folder_name: 'S3 gate / Sub' }
      expect(response).to have_http_status(:ok)

      api :get, '/api/ccn/template_folders'
      expect(response).to have_http_status(:ok)
      sub = json['data'].find { |f| f['id'] == sub_id }
      expect(sub).to include('templates_count' => 1, 'full_name' => 'S3 gate / Sub')
      expect(json['data'].pluck('name')).to include('S3 gate')

      api :put, "/api/ccn/template_folders/#{sub_id}", { name: 'Renamed' }
      expect(response).to have_http_status(:ok)
      expect(json).to include('name' => 'Renamed', 'full_name' => 'S3 gate / Renamed')

      api :delete, "/api/ccn/template_folders/#{sub_id}"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_folder_not_empty'))

      api :put, "/api/templates/#{template.id}", { folder_name: 'Default' }
      api :delete, "/api/ccn/template_folders/#{sub_id}"
      expect(response).to have_http_status(:ok)
      expect(json['archived_at']).to be_present
      expect(TemplateFolder.find(sub_id).archived_at).to be_present
    end

    it 'keeps the default folder immutable and hides other accounts' do
      default = template.account.default_template_folder

      api :put, "/api/ccn/template_folders/#{default.id}", { name: 'Nope' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_default_folder_immutable'))

      api :delete, "/api/ccn/template_folders/#{default.id}"
      expect(response).to have_http_status(:unprocessable_content)

      stranger = create(:template_folder)
      api :put, "/api/ccn/template_folders/#{stranger.id}", { name: 'X' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe '/api/ccn/templates/{id}/versions' do
    it 'snapshots idempotently, lists newest first, shows and restores a version' do
      original_name = template.name

      api :post, "/api/ccn/templates/#{template.id}/versions"
      expect(response).to have_http_status(:ok)
      first_id = json['id']
      expect(json['author']).to include('email' => admin.email)

      api :post, "/api/ccn/templates/#{template.id}/versions"
      expect(json['id']).to eq(first_id)

      template.update!(name: 'Renamed', fields: [])

      api :post, "/api/ccn/templates/#{template.id}/versions"
      second_id = json['id']
      expect(second_id).not_to eq(first_id)

      api :get, "/api/ccn/templates/#{template.id}/versions"
      expect(json['data'].pluck('id')).to eq([second_id, first_id])

      api :get, "/api/ccn/templates/#{template.id}/versions/#{first_id}"
      expect(response).to have_http_status(:ok)
      expect(json['data']).to include('name' => original_name)
      expect(json['data']['fields']).not_to be_empty
      expect(json['data']['documents'].size).to eq(1)

      api :post, "/api/ccn/templates/#{template.id}/versions/#{first_id}/restore"
      expect(response).to have_http_status(:ok)
      expect(json).to include('name' => original_name)
      expect(json['fields']).not_to be_empty
      expect(template.reload.name).to eq(original_name)
      expect(template.template_versions.count).to eq(2) # the pre-restore state was already version 2
    end

    it 'refuses to restore a version whose documents are gone, changing nothing' do
      data = TemplateVersions.build_data(template).merge('schema' => [{ 'attachment_uuid' => 'gone', 'name' => 'x' }])
      version = template.template_versions.create!(account:, author: admin, sha1: 'bogus', data:)

      api :post, "/api/ccn/templates/#{template.id}/versions/#{version.id}/restore"

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_version_documents_missing'))
      expect(template.reload.schema.first['attachment_uuid']).not_to eq('gone')

      api :get, "/api/ccn/templates/#{create(:template).id}/versions"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/ccn/templates/{id}/detect_fields' do
    before do
      allow(Templates::DetectFields).to receive(:call) do |_io, attachment:, page_number:, **, &block|
        index = page_number || 0
        fields = [{ uuid: SecureRandom.uuid, type: 'text', required: false, preferences: {},
                    areas: [{ x: 0.61, y: 0.93, w: 0.1, h: 0.03, page: index, attachment_uuid: attachment.uuid }] }]

        block&.call([attachment.uuid, index, fields])

        [fields, nil]
      end
    end

    it 'returns the candidates grouped by document and page, and applies them once on request' do
      attachment_uuid = template.schema.first['attachment_uuid']

      api :post, "/api/ccn/templates/#{template.id}/detect_fields", { page: 1 }
      expect(response).to have_http_status(:ok)
      expect(json['applied']).to eq(0)
      expect(json['documents'].size).to eq(1)
      expect(json['documents'].first).to include('attachment_uuid' => attachment_uuid)
      expect(json['documents'].first['pages'].first).to include('page' => 1)
      expect(json['documents'].first['pages'].first['fields'].first).to include('type' => 'text')
      expect(Templates::DetectFields).to have_received(:call).with(anything, hash_including(page_number: 0))

      fields_before = template.fields.size

      api :post, "/api/ccn/templates/#{template.id}/detect_fields", { apply: true, attachment_uuid: }
      expect(response).to have_http_status(:ok)
      expect(json['applied']).to eq(1)
      expect(template.reload.fields.size).to eq(fields_before + 1)
      expect(template.fields.last).to include('name' => '', 'submitter_uuid' => template.submitters.first['uuid'],
                                              'type' => 'text')

      api :post, "/api/ccn/templates/#{template.id}/detect_fields", { apply: true }
      expect(json['applied']).to eq(0) # the same candidate overlaps the field just added
      expect(template.reload.fields.size).to eq(fields_before + 1)
    end

    it 'refuses a bad page, a template without documents and too many pages' do
      api :post, "/api/ccn/templates/#{template.id}/detect_fields", { page: 0 }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_invalid_page'))

      empty = create(:template, account:, author: admin, attachment_count: 0)
      api :post, "/api/ccn/templates/#{empty.id}/detect_fields"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_no_documents'))

      stub_const('Ccn::DetectTemplateFields::MAX_PAGES', 0)
      api :post, "/api/ccn/templates/#{template.id}/detect_fields"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_too_many_pages', max: 0))
    end
  end
end
