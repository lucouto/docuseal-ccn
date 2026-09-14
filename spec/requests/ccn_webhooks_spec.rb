# frozen_string_literal: true

# CCN fork — Stage 3, user story 2 (specs/002-everything-by-api): webhooks administered by API.
describe 'CCN webhooks API' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account:) }
  let(:headers) { { 'x-auth-token': admin.access_token.token, 'Content-Type': 'application/json' } }

  def json
    response.parsed_body
  end

  def api(method, path, body = nil)
    public_send(method, path, headers:, params: body&.to_json)
  end

  describe 'POST / GET / PUT / DELETE /api/ccn/webhooks' do
    it 'creates a webhook with the default events, lists it without secrets and reveals them on request' do
      api :post, '/api/ccn/webhooks', { url: 'https://n8n.example.com/hook', secret: { key: 'X-Token', value: 's3' } }

      expect(response).to have_http_status(:ok)
      expect(json).to include('url' => 'https://n8n.example.com/hook', 'secret_key' => 'X-Token',
                              'events' => %w[form.viewed form.started form.completed form.declined])
      expect(json.keys).not_to include('secret', 'hmac_secret')

      webhook = WebhookUrl.find(json['id'])
      expect(webhook.account).to eq(account)
      expect(webhook.secret).to eq('X-Token' => 's3')

      api :get, '/api/ccn/webhooks'
      expect(json['data'].pluck('id')).to eq([webhook.id])
      expect(json['data'].first.keys).to contain_exactly('id', 'url', 'events', 'secret_key', 'created_at',
                                                         'updated_at')

      api :get, "/api/ccn/webhooks/#{webhook.id}/secret"
      expect(json).to eq('secret' => { 'X-Token' => 's3' }, 'hmac_secret' => webhook.hmac_secret)
      expect(webhook.hmac_secret).to be_present

      api :put, "/api/ccn/webhooks/#{webhook.id}", { events: ['form.completed', 'submission.completed'], secret: {} }
      expect(response).to have_http_status(:ok)
      expect(json).to include('events' => ['form.completed', 'submission.completed'], 'secret_key' => nil)
      expect(webhook.reload.secret).to eq({})

      api :delete, "/api/ccn/webhooks/#{webhook.id}"
      expect(response).to have_http_status(:ok)
      expect(json).to eq('id' => webhook.id, 'deleted' => true)
      expect(WebhookUrl.exists?(webhook.id)).to be(false)
    end

    it 'refuses unknown events and URLs that are not http(s), naming the offending value' do
      api :post, '/api/ccn/webhooks', { url: 'https://n8n.example.com/hook', events: ['form.completed', 'form.nope'] }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to include('form.nope')

      api :post, '/api/ccn/webhooks', { url: 'ftp://files.example.com' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_invalid_webhook_url'))

      api :post, '/api/ccn/webhooks', { url: 'not a url' }
      expect(response).to have_http_status(:unprocessable_content)

      expect(WebhookUrl.count).to eq(0)
    end

    it 'answers 404 for a webhook of another account' do
      stranger = create(:webhook_url)

      api :get, "/api/ccn/webhooks/#{stranger.id}"
      expect(response).to have_http_status(:not_found)

      api :get, "/api/ccn/webhooks/#{stranger.id}/secret"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'deliveries, resend and test' do
    let(:webhook) { create(:webhook_url, account:, url: 'https://n8n.example.com/hook') }
    let(:template) { create(:template, account:, author: admin) }
    let(:submission) { create(:submission, :with_submitters, template:) }

    it 'lists the deliveries with their attempts, filters by status and re-queues one' do
      submitter = submission.submitters.first
      ok = WebhookEvent.create!(webhook_url: webhook, account:, event_type: 'form.completed', record: submitter,
                                status: 'success')
      failed = WebhookEvent.create!(webhook_url: webhook, account:, event_type: 'form.completed', record: submitter,
                                    status: 'error')
      WebhookAttempt.create!(webhook_event: failed, attempt: 1, response_status_code: 500)
      WebhookAttempt.create!(webhook_event: failed, attempt: 2, response_status_code: 502)

      api :get, "/api/ccn/webhooks/#{webhook.id}/events"
      expect(response).to have_http_status(:ok)
      expect(json['data'].pluck('uuid')).to eq([failed.uuid, ok.uuid]) # newest first
      expect(json['data'].first).to include('event_type' => 'form.completed', 'record_type' => 'Submitter',
                                            'record_id' => submitter.id, 'status' => 'error')
      expect(json['data'].first['attempts'].pluck('response_status_code')).to eq([500, 502])

      api :get, "/api/ccn/webhooks/#{webhook.id}/events?status=error"
      expect(json['data'].pluck('uuid')).to eq([failed.uuid])

      api :get, "/api/ccn/webhooks/#{webhook.id}/events?status=weird"
      expect(response).to have_http_status(:unprocessable_content)

      expect { api :post, "/api/ccn/webhooks/#{webhook.id}/events/#{failed.uuid}/resend" }
        .to change(SendFormCompletedWebhookRequestJob.jobs, :size).by(1)
      expect(response).to have_http_status(:ok)
      expect(json).to eq('queued' => true, 'event_uuid' => failed.uuid)
      expect(SendFormCompletedWebhookRequestJob.jobs.last['args'].first)
        .to include('submitter_id' => submitter.id, 'webhook_url_id' => webhook.id, 'event_uuid' => failed.uuid,
                    'attempt' => SendWebhookRequest::MANUAL_ATTEMPT, 'last_status' => 0)

      api :post, "/api/ccn/webhooks/#{webhook.id}/events/nope/resend"
      expect(response).to have_http_status(:not_found)
    end

    it 'queues a test delivery from the last completed submitter, or refuses without one' do
      api :post, "/api/ccn/webhooks/#{webhook.id}/test"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('ccn_no_completed_submitter'))

      submission.submitters.first.update!(completed_at: Time.current)

      expect { api :post, "/api/ccn/webhooks/#{webhook.id}/test" }
        .to change(SendTestWebhookRequestJob.jobs, :size).by(1)
      expect(response).to have_http_status(:ok)
      expect(json).to include('queued' => true)
      expect(SendTestWebhookRequestJob.jobs.last['args'].first)
        .to include('submitter_id' => submission.submitters.first.id, 'webhook_url_id' => webhook.id)
    end
  end
end
