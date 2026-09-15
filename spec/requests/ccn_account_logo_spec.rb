# frozen_string_literal: true

# CCN fork — Stage 4, US2 (specs/003-p1-features): GET/PUT/DELETE /api/ccn/account_logo.
describe 'CCN account logo API' do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': admin.access_token.token, 'Content-Type': 'application/json' } }
  let(:png_bytes) { Rails.root.join('spec/fixtures/sample-image.png').binread }
  let(:png_base64) { Base64.strict_encode64(png_bytes) }
  let(:svg_bytes) { '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>' }

  def json
    response.parsed_body
  end

  def api(method, path, body = nil)
    public_send(method, path, headers:, params: body&.to_json)
  end

  describe 'GET /api/ccn/account_logo' do
    it 'is 404 while no logo is attached' do
      api :get, '/api/ccn/account_logo'

      expect(response).to have_http_status(:not_found)
      expect(json['error']).to be_present
    end

    it 'describes the stored logo' do
      api :put, '/api/ccn/account_logo', { file: png_base64, name: 'chemin-neuf' }
      expect(response).to have_http_status(:ok)

      api :get, '/api/ccn/account_logo'

      expect(response).to have_http_status(:ok)
      expect(json).to match('url' => %r{\Ahttps?://.+/file/.+},
                            'filename' => 'chemin-neuf.png',
                            'content_type' => 'image/png',
                            'byte_size' => png_bytes.bytesize)
    end
  end

  describe 'PUT /api/ccn/account_logo' do
    it 'accepts base64' do
      api :put, '/api/ccn/account_logo', { file: png_base64 }

      expect(response).to have_http_status(:ok)
      expect(account.reload.logo).to be_attached
      expect(account.logo.download).to eq(png_bytes)
    end

    it 'accepts a data URI' do
      api :put, '/api/ccn/account_logo', { file: "data:image/png;base64,#{png_base64}" }

      expect(response).to have_http_status(:ok)
      expect(account.reload.logo.download).to eq(png_bytes)
    end

    it 'accepts an https URL' do
      stub_request(:get, 'https://files.example.com/logo.png').to_return(status: 200, body: png_bytes)

      api :put, '/api/ccn/account_logo', { file: 'https://files.example.com/logo.png' }

      expect(response).to have_http_status(:ok)
      expect(json['filename']).to eq('logo.png')
      expect(account.reload.logo.download).to eq(png_bytes)
    end

    it 'replaces a logo already stored' do
      api :put, '/api/ccn/account_logo', { file: png_base64 }
      first_blob_id = account.reload.logo.blob.id

      api :put, '/api/ccn/account_logo', { file: Base64.strict_encode64(png_bytes + "\x00".b) }

      expect(response).to have_http_status(:ok)
      expect(account.reload.logo.blob.id).not_to eq(first_blob_id)
    end

    it 'refuses an SVG and stores nothing' do
      api :put, '/api/ccn/account_logo', { file: Base64.strict_encode64(svg_bytes) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('The logo must be a PNG, JPEG or WebP image')
      expect(account.reload.logo).not_to be_attached
    end

    it 'refuses an image over 2 MB' do
      oversize = png_bytes + ("\x00".b * (2.megabytes + 1))

      api :put, '/api/ccn/account_logo', { file: Base64.strict_encode64(oversize) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('The logo must be at most 2 MB')
      expect(account.reload.logo).not_to be_attached
    end

    it 'keeps the logo already stored when a replacement is refused' do
      api :put, '/api/ccn/account_logo', { file: png_base64 }
      blob_id = account.reload.logo.blob.id

      api :put, '/api/ccn/account_logo', { file: Base64.strict_encode64(svg_bytes) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(account.reload.logo.blob.id).to eq(blob_id)
    end

    it 'names the offending key when the file is missing' do
      api :put, '/api/ccn/account_logo', {}

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('file is required')
    end

    it 'names the offending key when the file is not base64' do
      api :put, '/api/ccn/account_logo', { file: 'not base64 at all !!' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('file is not valid base64 (or an https URL)')
    end
  end

  # The settings page is the only route that takes a file upload: ApiPathConsiderJsonMiddleware reads every
  # /api request as JSON, so the API takes base64/data URI/URL and this form takes the multipart.
  describe 'Settings → Personalization → Company logo' do
    def upload_of(bytes, filename, content_type)
      tempfile = Tempfile.new(['logo', File.extname(filename)])
      tempfile.binmode
      tempfile.write(bytes)
      tempfile.rewind

      Rack::Test::UploadedFile.new(tempfile, content_type, original_filename: filename)
    end

    before { sign_in(admin) }

    it 'stores an uploaded image and shows it on the page' do
      post '/settings/personalization_logo', params: { file: upload_of(png_bytes, 'logo.png', 'image/png') }

      expect(response).to redirect_to(settings_personalization_path)
      expect(account.reload.logo).to be_attached

      get '/settings/personalization'

      expect(response.body).to include(ActiveStorage::Blob.proxy_path(account.logo.blob))
    end

    it 'refuses a file that is not one of the three image types' do
      post '/settings/personalization_logo', params: { file: upload_of(svg_bytes, 'logo.svg', 'image/svg+xml') }

      expect(flash[:alert]).to eq('The logo must be a PNG, JPEG or WebP image')
      expect(account.reload.logo).not_to be_attached
    end

    it 'asks for a file when the form is submitted without one' do
      post '/settings/personalization_logo'

      expect(flash[:alert]).to eq('Choose an image file to upload')
      expect(account.reload.logo).not_to be_attached
    end

    it 'removes the logo' do
      post '/settings/personalization_logo', params: { file: upload_of(png_bytes, 'logo.png', 'image/png') }

      delete '/settings/personalization_logo'

      expect(response).to redirect_to(settings_personalization_path)
      expect(account.reload.logo).not_to be_attached
    end

    it 'refuses a signed-in editor' do
      sign_in(create(:user, account:, role: 'editor'))

      post '/settings/personalization_logo', params: { file: upload_of(png_bytes, 'logo.png', 'image/png') }

      expect(response).to redirect_to(root_path)
      expect(account.reload.logo).not_to be_attached
    end
  end

  # FR-007: the logo replaces the DocuSeal mark in the header of the pages a signer sees and in the e-mails
  # they receive — and the DocuSeal attribution in the footer is the same text either way (AGPL §7(b)).
  describe 'the pages a signer sees' do
    let(:template) { create(:template, account:, author: admin, only_field_types: %w[text]) }
    let(:submission) { create(:submission, :with_submitters, template:) }
    let(:submitter) { submission.submitters.first }

    # shared/_powered_by, the only block with this class — rendered by shared/_attribution on every such page.
    def attribution
      response.body[%r{<div class="text-center px-2">.*?</div>}m]
    end

    def logo_path
      ActiveStorage::Blob.proxy_path(account.reload.logo.blob)
    end

    it 'shows the DocuSeal mark while no logo is attached' do
      get "/s/#{submitter.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('viewBox="0 0 180 180"')
      expect(attribution).to include('DocuSeal').and include(Ccn::SOURCE_URL)
    end

    it 'shows the logo instead, with the attribution unchanged' do
      get "/s/#{submitter.slug}"
      attribution_without_logo = attribution

      api :put, '/api/ccn/account_logo', { file: png_base64 }
      expect(response).to have_http_status(:ok)

      get "/s/#{submitter.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(logo_path)
      expect(response.body).not_to include('viewBox="0 0 180 180"')
      expect(attribution).to eq(attribution_without_logo)
    end

    it 'shows the logo on the start form as well' do
      template.update!(shared_link: true)
      api :put, '/api/ccn/account_logo', { file: png_base64 }

      get "/d/#{template.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(logo_path)
      expect(attribution).to include('DocuSeal')
    end

    it 'brings the mark back once the logo is removed' do
      api :put, '/api/ccn/account_logo', { file: png_base64 }
      api :delete, '/api/ccn/account_logo'

      get "/s/#{submitter.slug}"

      expect(response.body).to include('viewBox="0 0 180 180"')
      expect(attribution).to include('DocuSeal')
    end
  end

  describe 'the e-mails a signer receives' do
    let(:template) { create(:template, account:, author: admin, only_field_types: %w[text]) }
    let(:submission) { create(:submission, :with_submitters, template:) }
    let(:submitter) { submission.submitters.first }
    # Long URLs are folded by quoted-printable, so assertions read the decoded body, not the wire form.
    let(:html) { SubmitterMailer.invitation_email(submitter).body.decoded }

    def app_url_known!
      create(:encrypted_config, account:, key: EncryptedConfig::APP_URL_KEY, value: 'https://docuseal.test')
    end

    it 'carries the logo and keeps the DocuSeal attribution' do
      app_url_known!
      api :put, '/api/ccn/account_logo', { file: png_base64 }

      expect(html).to include(ActiveStorage::Blob.proxy_url(account.reload.logo.blob))
      expect(html).to include('DocuSeal')
    end

    it 'is unchanged when no logo is attached' do
      app_url_known!

      expect(html).not_to include('<img')
      expect(html).to include('DocuSeal')
    end

    # A logo the instance cannot address absolutely would reach the inbox as a broken image.
    it 'leaves the logo out when the instance does not know its own URL' do
      api :put, '/api/ccn/account_logo', { file: png_base64 }

      expect(html).not_to include('<img')
    end
  end

  describe 'DELETE /api/ccn/account_logo' do
    it 'removes the logo' do
      api :put, '/api/ccn/account_logo', { file: png_base64 }

      api :delete, '/api/ccn/account_logo'

      expect(response).to have_http_status(:ok)
      expect(json).to eq('deleted' => true)
      expect(account.reload.logo).not_to be_attached

      api :get, '/api/ccn/account_logo'
      expect(response).to have_http_status(:not_found)
    end

    it 'is a no-op when there is no logo' do
      api :delete, '/api/ccn/account_logo'

      expect(response).to have_http_status(:ok)
      expect(json).to eq('deleted' => true)
    end
  end
end
