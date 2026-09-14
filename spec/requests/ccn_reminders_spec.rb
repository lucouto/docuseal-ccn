# frozen_string_literal: true

# CCN fork — Stage 4, US1 (specs/003-p1-features): GET /api/ccn/reminders/due, POST /api/ccn/reminders/run.
describe 'CCN reminders API' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': admin.access_token.token, 'Content-Type': 'application/json' } }
  let(:template) { create(:template, account:) }

  def json
    response.parsed_body
  end

  def api(method, path, body = nil)
    public_send(method, path, headers:, params: body&.to_json)
  end

  before do
    allow(Sidekiq).to receive(:redis) { |&block| block.call(FakeReminderRedis.new) }
  end

  it 'reports disabled when no reminders are configured' do
    api :post, '/api/ccn/reminders/run'

    expect(response).to have_http_status(:ok)
    expect(json).to eq('sent' => 0, 'skipped' => {}, 'locked' => false, 'disabled' => true)
  end

  it 'lists a due signer and then sends exactly one reminder' do
    api :put, '/api/ccn/account_configs/submitter_reminders', { value: { first_duration: 'one_hour' } }
    expect(response).to have_http_status(:ok)

    submission = create(:submission, template:)
    submitter = create(:submitter, submission:, account:, email: 'signer@example.com', sent_at: 2.hours.ago)

    api :get, '/api/ccn/reminders/due'

    expect(response).to have_http_status(:ok)
    expect(json['data']).to contain_exactly(include('submitter_id' => submitter.id, 'stage' => 1))

    api :post, '/api/ccn/reminders/run'

    expect(response).to have_http_status(:ok)
    expect(json).to eq('sent' => 1, 'skipped' => {}, 'locked' => false, 'disabled' => false)
    expect(submitter.submission_events.where(event_type: 'send_reminder_email')).to be_one
  end

  it 'dry_run counts without sending' do
    api :put, '/api/ccn/account_configs/submitter_reminders', { value: { first_duration: 'one_hour' } }

    submission = create(:submission, template:)
    submitter = create(:submitter, submission:, account:, email: 'signer@example.com', sent_at: 2.hours.ago)

    api :post, '/api/ccn/reminders/run', { dry_run: true }

    expect(json).to eq('sent' => 1, 'skipped' => {}, 'locked' => false, 'disabled' => false)
    expect(submitter.submission_events.where(event_type: 'send_reminder_email')).to be_none
  end

  it 'refuses an unauthenticated request' do
    get '/api/ccn/reminders/due'

    expect(response).to have_http_status(:unauthorized)
  end
end
