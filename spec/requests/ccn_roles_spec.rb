# frozen_string_literal: true

# CCN fork — Stage 4, US3 (specs/003-p1-features, SC-004): what an editor's and a viewer's API token can
# actually do. The rules themselves are spec/lib/ability_spec.rb; this is the 200/403 they produce through
# the controllers, with no role check written in any of them.
describe 'CCN roles' do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account:) }
  let(:editor) { create(:user, account:, role: 'editor') }
  let(:viewer) { create(:user, account:, role: 'viewer') }
  let(:template) { create(:template, account:, author: admin, only_field_types: %w[text]) }
  let(:pdf_base64) { Base64.strict_encode64(Rails.root.join('spec/fixtures/ccn/fieldtags.pdf').binread) }

  def json
    response.parsed_body
  end

  def as(user, method, path, body = nil)
    headers = { 'x-auth-token': user.access_token.token, 'Content-Type': 'application/json' }

    public_send(method, path, headers:, params: body&.to_json)
  end

  describe 'the /api/ccn administration endpoints' do
    # FR-008: these answer 403 through the authorize! calls they already had — no controller learned about
    # roles.
    admin_only = {
      'users' => '/api/ccn/users',
      'webhooks' => '/api/ccn/webhooks',
      'account configs' => '/api/ccn/account_configs',
      'reminders' => '/api/ccn/reminders/due'
    }

    admin_only.each do |name, path|
      it "refuses an editor on #{name}" do
        as(editor, :get, path)

        expect(response).to have_http_status(:forbidden)
      end

      it "refuses a viewer on #{name}" do
        as(viewer, :get, path)

        expect(response).to have_http_status(:forbidden)
      end
    end

    # Folders belong to the documents an editor works with, so they are theirs to manage. The whole namespace
    # asks for `manage` in one before_action, index included, so a viewer is refused even on the list — noted
    # on the operation in docs/openapi-ccn.json rather than worked around with a second authorize! call.
    it 'lets an editor manage template folders' do
      as(editor, :get, '/api/ccn/template_folders')
      expect(response).to have_http_status(:ok)

      as(editor, :post, '/api/ccn/template_folders', { name: 'Conventions' })
      expect(response).to have_http_status(:ok)
    end

    it 'refuses a viewer on template folders, listing included' do
      as(viewer, :get, '/api/ccn/template_folders')

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses an editor running the reminders' do
      as(editor, :post, '/api/ccn/reminders/run', { dry_run: true })

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses an editor changing the account logo' do
      as(editor, :put, '/api/ccn/account_logo', { file: pdf_base64 })

      expect(response).to have_http_status(:forbidden)
    end

    it 'still serves an administrator' do
      as(admin, :get, '/api/ccn/users')

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'documents and sending' do
    it 'lets an editor create a template and a submission' do
      as(editor, :post, '/api/templates/pdf', { documents: [{ name: 'lease', file: pdf_base64 }] })
      expect(response).to have_http_status(:ok)

      created_id = json['id']

      as(editor, :post, '/api/submissions',
         { template_id: created_id, send_email: false,
           submitters: [{ role: 'First Party', email: 'signer@example.com' }] })

      expect(response).to have_http_status(:ok)
    end

    it 'refuses a viewer creating a template' do
      as(viewer, :post, '/api/templates/pdf', { documents: [{ name: 'lease', file: pdf_base64 }] })

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a viewer creating a submission' do
      as(viewer, :post, '/api/submissions',
         { template_id: template.id, send_email: false,
           submitters: [{ role: 'First Party', email: 'signer@example.com' }] })

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a viewer archiving a template' do
      as(viewer, :delete, "/api/templates/#{template.id}")

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'reading' do
    let(:submission) { create(:submission, :with_submitters, template:) }

    it 'lets both roles list templates' do
      [editor, viewer].each do |user|
        as(user, :get, '/api/templates')

        expect(response).to have_http_status(:ok)
        expect(json['data'].pluck('id')).to include(template.id)
      end
    end

    it 'lets both roles read a submission and its documents' do
      [editor, viewer].each do |user|
        as(user, :get, "/api/submissions/#{submission.id}")
        expect(response).to have_http_status(:ok)

        as(user, :get, "/api/submissions/#{submission.id}/documents")
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # FR-009: the account keeps an administrator. The self-guards in the UI and in Ccn::ManageUsers mean the
  # last administrator cannot demote themselves, so the reachable way to empty the set is somebody else doing
  # it — and the automation account is exactly the "somebody else" that must not be able to.
  describe 'the last administrator' do
    let(:integration) { create(:user, account:, role: 'integration') }

    it 'cannot be archived by the integration user through the API' do
      as(integration, :delete, "/api/ccn/users/#{admin.id}")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('At least one administrator must remain on the account')
      expect(admin.reload.archived_at).to be_nil
    end

    it 'cannot be demoted by the integration user through the API' do
      as(integration, :put, "/api/ccn/users/#{admin.id}", { role: 'viewer' })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('At least one administrator must remain on the account')
      expect(admin.reload.role).to eq('admin')
    end

    it 'can be demoted once a second administrator exists' do
      create(:user, account:)

      as(integration, :put, "/api/ccn/users/#{admin.id}", { role: 'editor' })

      expect(response).to have_http_status(:ok)
      expect(admin.reload.role).to eq('editor')
    end

    # UsersController#update does not strip archived_at for the current user, so this is the reachable UI path
    # — and UsersController#destroy archives with update!, which without Ccn::UsersControllerGuard is a 500.
    it 'cannot archive themselves from the settings page' do
      sign_in(admin)

      put "/users/#{admin.id}", params: { user: { archived_at: Time.current.iso8601 } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(admin.reload.archived_at).to be_nil
    end

    it 'is refused, not crashed, when the guard fires on the archive button' do
      sign_in(integration)

      delete "/users/#{admin.id}"

      expect(response).to redirect_to(settings_users_path)
      expect(flash[:alert]).to eq('At least one administrator must remain on the account')
      expect(admin.reload.archived_at).to be_nil
    end
  end

  describe 'the users settings page' do
    it 'offers the editor and viewer roles' do
      sign_in(admin)

      get '/users/new'

      expect(response.body).to include('<option value="editor">').and include('<option value="viewer">')
    end

    it 'lets an editor see the list without the means to change it' do
      sign_in(editor)

      get '/settings/users'

      expect(response).to have_http_status(:ok)
    end
  end
end
