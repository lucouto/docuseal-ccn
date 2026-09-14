# frozen_string_literal: true

# CCN fork — the template preferences allow-list behind PUT /api/templates/{id} (specs/002-everything-by-api).
describe Ccn::TemplatePreferences do
  let(:account) { create(:account, timezone: 'Europe/Paris') }
  let(:template) { create(:template, account:, author: create(:user, account:)) }

  it 'mirrors the keys the UI permits' do
    expect(described_class::KEYS.size).to eq(31) # 28 scalar keys + 3 nested, as TemplatesPreferencesController
    expect(described_class::KEYS).to include('request_email_subject', 'default_expire_at', 'completed_message',
                                             'submitters', 'link_form_fields')
  end

  it 'merges coerced values, removes keys on null or blank, and keeps the others' do
    template.preferences = { 'request_email_subject' => 'Old', 'bcc_completed' => 'x@y.z' }

    described_class.apply!(template, { 'request_email_subject' => 'New', 'require_email_2fa' => 'true',
                                       'documents_copy_email_enabled' => false, 'bcc_completed' => nil,
                                       'completed_message' => { 'title' => 'Done', 'body' => '' },
                                       'link_form_fields' => ['a', '', 'b'],
                                       'submitters' => [{ 'uuid' => 'u1', 'request_email_subject' => 'S' }] },
                           account)

    expect(template.preferences).to eq('request_email_subject' => 'New', 'require_email_2fa' => true,
                                       'documents_copy_email_enabled' => false,
                                       'completed_message' => { 'title' => 'Done' },
                                       'link_form_fields' => %w[a b],
                                       'submitters' => [{ 'uuid' => 'u1', 'request_email_subject' => 'S' }])

    described_class.apply!(template, { 'completed_message' => { 'title' => '' }, 'request_email_subject' => '' },
                           account)
    expect(template.preferences.keys).not_to include('completed_message', 'request_email_subject')
  end

  it 'interprets default_expire_at in the account timezone and stores UTC' do
    described_class.apply!(template, { 'default_expire_at' => '2027-01-15 10:00' }, account)

    # the serialized attribute round-trips through JSON on assignment
    expect(template.preferences['default_expire_at']).to eq('2027-01-15T09:00:00.000Z')

    expect { described_class.apply!(template, { 'default_expire_at' => 'someday' }, account) }
      .to raise_error(Ccn::AdminInvalid, /datetime/)
    expect { described_class.apply!(template, { 'default_expire_at' => 12 }, account) }
      .to raise_error(Ccn::AdminInvalid, /datetime/)
  end

  it 'refuses unknown keys, unknown nested members and wrong shapes' do
    expect { described_class.apply!(template, { 'colour' => 'red' }, account) }
      .to raise_error(Ccn::AdminInvalid, I18n.t('ccn_unknown_preference', key: 'colour'))
    expect { described_class.apply!(template, { 'completed_message' => { 'footer' => 'x' } }, account) }
      .to raise_error(Ccn::AdminInvalid, /title, body/)
    expect { described_class.apply!(template, { 'completed_message' => 'plain' }, account) }
      .to raise_error(Ccn::AdminInvalid, /object/)
    expect { described_class.apply!(template, { 'submitters' => { 'uuid' => 'u' } }, account) }
      .to raise_error(Ccn::AdminInvalid, /list/)
    expect { described_class.apply!(template, { 'request_email_subject' => { 'a' => 1 } }, account) }
      .to raise_error(Ccn::AdminInvalid, /string or boolean/)
    expect { described_class.apply!(template, 'nope', account) }
      .to raise_error(Ccn::AdminInvalid, /object/)
  end
end
