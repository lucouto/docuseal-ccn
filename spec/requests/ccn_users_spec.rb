# frozen_string_literal: true

# CCN fork — Stage 3, user story 1 (specs/002-everything-by-api): users administered by API with the rules
# of the UI's UsersController.
describe 'CCN users API' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': admin.access_token.token, 'Content-Type': 'application/json' } }

  def json
    response.parsed_body
  end

  def api(method, path, body = nil)
    public_send(method, path, headers:, params: body&.to_json)
  end

  describe 'GET /api/ccn/users' do
    it 'lists active users by default, archived and integration users on request, without secrets' do
      colleague = create(:user, account:)
      archived = create(:user, account:, archived_at: Time.current)
      integration = create(:user, account:, role: 'integration')
      create(:user) # another account

      api :get, '/api/ccn/users'
      expect(response).to have_http_status(:ok)
      expect(json['data'].pluck('id')).to contain_exactly(admin.id, colleague.id)
      expect(json['data'].first.keys).to match_array(%w[id email first_name last_name role archived_at
                                                        otp_required_for_login current_sign_in_at last_sign_in_at
                                                        created_at updated_at])
      expect(json['pagination']).to include('count' => 2)

      api :get, '/api/ccn/users?status=archived'
      expect(json['data'].pluck('id')).to eq([archived.id])

      api :get, '/api/ccn/users?status=integration'
      expect(json['data'].pluck('id')).to eq([integration.id])

      api :get, '/api/ccn/users?status=nope'
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to include('nope')
    end

    it 'refuses a missing token' do
      get '/api/ccn/users'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/ccn/users' do
    it 'invites a user with the default role and password and queues the invitation e-mail' do
      mail = instance_double(ActionMailer::MessageDelivery, deliver_later!: true)
      allow(UserMailer).to receive(:invitation_email).and_return(mail)

      api :post, '/api/ccn/users', { email: 'new@example.com', first_name: 'New', last_name: 'Person' }

      expect(response).to have_http_status(:ok)
      expect(json).to include('email' => 'new@example.com', 'first_name' => 'New', 'role' => 'admin',
                              'archived_at' => nil)
      expect(json).not_to have_key('uuid')

      user = User.find(json['id'])
      expect(user.account).to eq(account)
      expect(user.encrypted_password).to be_present
      expect(UserMailer).to have_received(:invitation_email).with(user, invited_by: admin)
      expect(mail).to have_received(:deliver_later!)
    end

    it 'skips the e-mail with send_email false and refuses an unknown role' do
      allow(UserMailer).to receive(:invitation_email)

      api :post, '/api/ccn/users', { email: 'quiet@example.com', send_email: false }
      expect(response).to have_http_status(:ok)
      expect(UserMailer).not_to have_received(:invitation_email)

      api :post, '/api/ccn/users', { email: 'x@example.com', role: 'superuser', send_email: false }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to include('superuser')
    end

    it 'reactivates an archived user with the same e-mail and refuses an active duplicate' do
      archived = create(:user, account:, email: 'back@example.com', first_name: 'Old', archived_at: 1.day.ago)

      api :post, '/api/ccn/users', { email: 'back@example.com', first_name: 'Back', send_email: false }
      expect(response).to have_http_status(:ok)
      expect(json['id']).to eq(archived.id)
      expect(json).to include('first_name' => 'Back', 'archived_at' => nil)

      api :post, '/api/ccn/users', { email: 'back@example.com', send_email: false }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_user_exists'))

      api :post, '/api/ccn/users', { first_name: 'No email', send_email: false }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to be_present
    end
  end

  describe 'PUT / DELETE /api/ccn/users/{id}' do
    it 'updates a colleague, guards the caller against itself and archives' do
      colleague = create(:user, account:, first_name: 'A')

      api :put, "/api/ccn/users/#{colleague.id}", { first_name: 'B', otp_required_for_login: true, password: '' }
      expect(response).to have_http_status(:ok)
      expect(json).to include('first_name' => 'B', 'otp_required_for_login' => true)

      api :put, "/api/ccn/users/#{admin.id}", { role: 'admin' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_self_change_refused'))

      api :put, "/api/ccn/users/#{admin.id}", { last_name: 'Me' }
      expect(response).to have_http_status(:ok)
      expect(json['last_name']).to eq('Me')

      api :delete, "/api/ccn/users/#{admin.id}"
      expect(response).to have_http_status(:unprocessable_content)

      api :delete, "/api/ccn/users/#{colleague.id}"
      expect(response).to have_http_status(:ok)
      expect(json['archived_at']).to be_present

      api :put, "/api/ccn/users/#{colleague.id}", { archived: false }
      expect(response).to have_http_status(:ok)
      expect(json['archived_at']).to be_nil
    end

    it 'answers 404 for a user of another account' do
      stranger = create(:user)

      api :get, "/api/ccn/users/#{stranger.id}"
      expect(response).to have_http_status(:not_found)
      expect(json['error']).to eq(I18n.t('ccn_not_found'))

      api :put, "/api/ccn/users/#{stranger.id}", { first_name: 'X' }
      expect(response).to have_http_status(:not_found)
      expect(stranger.reload.first_name).not_to eq('X')
    end
  end

  describe 'POST /api/ccn/users/{id}/reset_password' do
    it 'sends the reset instructions once per 10 minutes and never for an archived user' do
      colleague = create(:user, account:)

      api :post, "/api/ccn/users/#{colleague.id}/reset_password"
      expect(response).to have_http_status(:ok)
      expect(json).to eq('sent' => true)
      expect(colleague.reload.reset_password_sent_at).to be_present

      api :post, "/api/ccn/users/#{colleague.id}/reset_password"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_reset_already_sent'))

      colleague.update!(archived_at: Time.current, reset_password_sent_at: nil)

      api :post, "/api/ccn/users/#{colleague.id}/reset_password"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_user_archived'))
    end
  end
end
