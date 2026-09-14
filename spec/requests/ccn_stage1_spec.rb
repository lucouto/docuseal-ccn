# frozen_string_literal: true

# CCN fork — Stage 1 gate (FORK-PLAN.md §10 S1): Pro switches on, Pro upsells off, formulas and
# conditions honoured server-side on completion.
describe 'CCN Stage 1' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user, only_field_types: %w[text]) }
  let(:submission) { create(:submission, :with_submitters, template:, created_by_user: user) }
  let(:submitter) { submission.submitters.first }

  # Strings and hosts that only appear in DocuSeal's own upsell UI (resolved at runtime, locale-aware).
  let(:upsell_markers) do
    [I18n.t('unlock_with_docuseal_pro'), I18n.t('upgrade'), 'docuseal.com/pricing', Docuseal::CONSOLE_URL,
     "#{Docuseal::CLOUD_URL}/sign_up"]
  end

  before { sign_in(user) }

  describe 'template builder switches' do
    it 'enables conditions and formulas in the builder' do
      get "/templates/#{template.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-with-conditions="true"')
      expect(response.body).to include('data-with-formula="true"')
    end
  end

  describe 'no Pro upsell on reachable pages' do
    it 'renders the admin pages without DocuSeal Pro upsells' do
      paths = [
        '/', '/settings/account', '/settings/personalization', '/settings/notifications', '/settings/esign',
        '/settings/users', '/users/new', '/settings/sso', '/settings/sms', "/templates/#{template.id}/edit",
        "/templates/#{template.id}/preferences", "/templates/#{template.id}/submissions/new",
        "/submissions/#{submission.id}"
      ]

      aggregate_failures do
        paths.each do |path|
          get path

          expect(response).to have_http_status(:ok), "#{path} → #{response.status}"

          upsell_markers.each do |marker|
            expect(response.body).not_to include(marker), "#{path} still contains #{marker.inspect}"
          end
        end
      end
    end

    it 'keeps the DocuSeal attribution and adds the source-code link on the signing page' do
      get "/s/#{submitter.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Docuseal::PRODUCT_URL)
      expect(response.body).to include(Ccn::SOURCE_URL)
    end
  end

  describe 'formulas and conditions on form completion' do
    let(:attachment_uuid) { template.schema.first['attachment_uuid'] }
    let(:submitter_uuid) { template.submitters.first['uuid'] }
    let(:uuids) { %w[a b total label bonus].index_with { SecureRandom.uuid } }
    let(:total_formula) { "ROUND({{#{uuids['a']}}} * {{#{uuids['b']}}}, 2)" }
    let(:label_formula) { "Total: {{#{uuids['total']}}} EUR" }
    let(:bonus_condition) { { 'field_uuid' => uuids['a'], 'action' => 'greater_than', 'value' => '10' } }

    def field(name, type, required: true, **extra)
      {
        'uuid' => uuids[name], 'submitter_uuid' => submitter_uuid, 'name' => name, 'type' => type,
        'required' => required, 'preferences' => {},
        'areas' => [{ 'attachment_uuid' => attachment_uuid, 'page' => 0,
                      'x' => 0.1, 'y' => 0.1, 'w' => 0.2, 'h' => 0.03 }]
      }.merge(extra)
    end

    before do
      template.update!(
        fields: [
          field('a', 'number'),
          field('b', 'number'),
          field('total', 'number', required: false, 'preferences' => { 'formula' => total_formula }),
          field('label', 'text', required: false, 'preferences' => { 'formula' => label_formula }),
          field('bonus', 'text', required: false, 'conditions' => [bonus_condition])
        ]
      )
    end

    it 'computes numeric and text formulas server-side and drops values whose condition is false' do
      put "/s/#{submitter.slug}", params: {
        completed: 'true',
        values: { uuids['a'] => '2', uuids['b'] => '3.25', uuids['bonus'] => 'should be dropped' }
      }

      expect(response).to have_http_status(:ok)

      submitter.reload

      expect(submitter.completed_at).to be_present
      expect(submitter.values[uuids['total']]).to eq(6.5)
      expect(submitter.values[uuids['label']]).to eq('Total: 6.5 EUR')
      expect(submitter.values).not_to have_key(uuids['bonus'])
    end

    it 'treats non-numeric referenced values as 0, like the signing form does' do
      template.update!(fields: template.fields.map do |f|
        next f unless f['name'] == 'total'

        f.merge('preferences' => { 'formula' => "{{#{uuids['a']}}} + {{#{uuids['b']}}} + 1" })
      end)

      put "/s/#{submitter.slug}", params: { completed: 'true', values: { uuids['a'] => 'abc', uuids['b'] => '2' } }

      expect(response).to have_http_status(:ok)
      expect(submitter.reload.values[uuids['total']]).to eq(3)
    end

    it 'uses the first item of an array value, like a single-choice multiple field' do
      template.update!(fields: template.fields.map do |f|
        case f['name']
        when 'b' then f.merge('type' => 'multiple', 'options' => [{ 'uuid' => SecureRandom.uuid, 'value' => '3' }])
        when 'total' then f.merge('preferences' => { 'formula' => "{{#{uuids['a']}}} * {{#{uuids['b']}}}" })
        else f
        end
      end)

      put "/s/#{submitter.slug}", params: { completed: 'true', values: { uuids['a'] => '2', uuids['b'] => ['3'] } }

      expect(response).to have_http_status(:ok)
      expect(submitter.reload.values[uuids['total']]).to eq(6)
    end

    it 'refuses to complete when a formula divides by zero' do
      template.update!(fields: template.fields.map do |f|
        f['name'] == 'total' ? f.merge('preferences' => { 'formula' => "{{#{uuids['a']}}} / 0" }) : f
      end)

      put "/s/#{submitter.slug}", params: { completed: 'true', values: { uuids['a'] => '2', uuids['b'] => '1' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_formula_error_zero_division'))
      expect(submitter.reload.completed_at).to be_nil
    end

    it 'refuses to complete when a formula has no real result, instead of failing with a 500' do
      template.update!(fields: template.fields.map do |f|
        f['name'] == 'total' ? f.merge('preferences' => { 'formula' => "{{#{uuids['a']}}} ^ {{#{uuids['b']}}}" }) : f
      end)

      # cast_number is what number_step.vue sends: -8 arrives as an Integer and 0.5 as a Float.
      put "/s/#{submitter.slug}", params: {
        completed: 'true', cast_number: 'true', values: { uuids['a'] => '-8', uuids['b'] => '0.5' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_formula_error_not_a_number'))
      expect(submitter.reload.completed_at).to be_nil
    end

    it 'refuses a result that does not fit a double instead of storing Infinity' do
      template.update!(fields: template.fields.map do |f|
        f['name'] == 'total' ? f.merge('preferences' => { 'formula' => "{{#{uuids['a']}}} ^ 400 + 0.5" }) : f
      end)

      put "/s/#{submitter.slug}", params: { completed: 'true', values: { uuids['a'] => '10', uuids['b'] => '1' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_formula_error_out_of_range'))
      expect(submitter.reload.completed_at).to be_nil
    end

    it 'refuses a signer-controlled exponent that would take minutes to compute exactly' do
      template.update!(fields: template.fields.map do |f|
        f['name'] == 'total' ? f.merge('preferences' => { 'formula' => "{{#{uuids['a']}}} ^ {{#{uuids['b']}}}" }) : f
      end)

      put "/s/#{submitter.slug}", params: {
        completed: 'true', values: { uuids['a'] => '7', uuids['b'] => '100000000' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_formula_error_out_of_range'))
      expect(submitter.reload.completed_at).to be_nil
    end

    it 'refuses a signer-controlled bit shift that would exhaust memory' do
      template.update!(fields: template.fields.map do |f|
        next f unless f['name'] == 'total'

        f.merge('preferences' => { 'formula' => "ROUND({{#{uuids['a']}}}) << {{#{uuids['b']}}}" })
      end)

      put "/s/#{submitter.slug}", params: {
        completed: 'true', values: { uuids['a'] => '1', uuids['b'] => '10000000000000000000' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_formula_error_out_of_range'))
      expect(submitter.reload.completed_at).to be_nil
    end

    it 'leaves the operands of a ^ alone when its IF branch is not taken' do
      template.update!(fields: template.fields.map do |f|
        next f unless f['name'] == 'total'

        f.merge('preferences' => { 'formula' => "IF({{#{uuids['a']}}} > 0, 1, {{#{uuids['b']}}} ^ 2000)" })
      end)

      put "/s/#{submitter.slug}", params: { completed: 'true', values: { uuids['a'] => '5', uuids['b'] => '7' } }

      expect(response).to have_http_status(:ok)
      expect(submitter.reload.values[uuids['total']]).to eq(1)
    end

    it 'counts an array with several items as 0, like a blank value' do
      options = %w[3 4].map { |v| { 'uuid' => SecureRandom.uuid, 'value' => v } }

      template.update!(fields: template.fields.map do |f|
        case f['name']
        when 'b' then f.merge('type' => 'multiple', 'options' => options)
        when 'total' then f.merge('preferences' => { 'formula' => "{{#{uuids['a']}}} * {{#{uuids['b']}}} + 1" })
        else f
        end
      end)

      put "/s/#{submitter.slug}", params: { completed: 'true', values: { uuids['a'] => '2', uuids['b'] => %w[3 4] } }

      expect(response).to have_http_status(:ok)
      expect(submitter.reload.values[uuids['total']]).to eq(1)
    end

    it 'shows a generic message for a broken formula, without dentaku internals' do
      template.update!(fields: template.fields.map do |f|
        f['name'] == 'total' ? f.merge('preferences' => { 'formula' => "foo + {{#{uuids['a']}}}" }) : f
      end)

      put "/s/#{submitter.slug}", params: { completed: 'true', values: { uuids['a'] => '2', uuids['b'] => '1' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_formula_error'))
      expect(submitter.reload.completed_at).to be_nil
    end

    it 'refuses a referenced value with more than 20 significant digits' do
      put "/s/#{submitter.slug}", params: {
        completed: 'true', values: { uuids['a'] => "1#{'0' * 25}", uuids['b'] => '1' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq(I18n.t('ccn_formula_error_out_of_range'))
      expect(submitter.reload.completed_at).to be_nil
    end

    it 'translates every formula error in English and French' do
      %w[ccn_formula_error ccn_formula_error_zero_division ccn_formula_error_not_a_number
         ccn_formula_error_out_of_range].each do |key|
        expect(I18n.exists?(key, :en)).to be(true)
        expect(I18n.exists?(key, :fr)).to be(true)
      end
    end
  end
end
