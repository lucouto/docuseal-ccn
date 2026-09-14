# frozen_string_literal: true

# CCN fork — Stage 4, US1 (specs/003-p1-features): the reminder e-mail block of the template preferences
# page. Subject and body fall back independently, so a body-only override (which PUT /api/templates/{id} and
# the set_template_preferences MCP tool can both save) cannot land in the subject field.
describe 'Template reminder e-mail preferences' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user) }

  before { sign_in(user) }

  def subject_field
    Nokogiri::HTML(response.body).at_css('input[name="template[preferences][invitation_reminder_email_subject]"]')
  end

  it 'keeps a body-only override out of the subject field' do
    template.update!(preferences: { 'invitation_reminder_email_body' => 'Merci de signer le document.' })

    get "/templates/#{template.id}/preferences"

    expect(response).to have_http_status(:ok)
    expect(subject_field['value']).not_to eq('Merci de signer le document.')
    expect(response.body).to include('Merci de signer le document.') # still rendered, as the body
  end

  it 'shows each template override in its own field' do
    template.update!(preferences: { 'invitation_reminder_email_subject' => 'Rappel de signature',
                                    'invitation_reminder_email_body' => 'Merci de signer le document.' })

    get "/templates/#{template.id}/preferences"

    expect(subject_field['value']).to eq('Rappel de signature')
    expect(response.body).to include('Merci de signer le document.')
  end

  it 'falls back to the account config when the template has no override' do
    AccountConfig.create!(account:, key: AccountConfig::SUBMITTER_INVITATION_REMINDER_EMAIL_KEY,
                          value: { 'subject' => 'Account subject', 'body' => 'Account body' })

    get "/templates/#{template.id}/preferences"

    expect(subject_field['value']).to eq('Account subject')
  end
end
