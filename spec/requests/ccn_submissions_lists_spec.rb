# frozen_string_literal: true

# CCN fork — Stage 4, US4 (specs/003-p1-features): the "Upload list" tab, from the file to the submissions.
describe 'CCN submissions lists' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, only_field_types: %w[text]) }

  before { sign_in(author) }

  def upload(content, filename = 'list.csv', content_type = 'text/csv')
    tempfile = Tempfile.new(['list', File.extname(filename)])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind

    Rack::Test::UploadedFile.new(tempfile, content_type, original_filename: filename)
  end

  def preview(content, send_email: '0')
    post "/templates/#{template.id}/submissions_lists/preview",
         params: { file: upload(content), send_email: }
  end

  def payload_from(body)
    body[/name="payload"[^>]*value="([^"]+)"/, 1] || body[/value="([^"]+)"[^>]*name="payload"/, 1]
  end

  it 'reads the file back before anything is sent' do
    preview("email,name\na@example.org,A\nb@example.org,B\n")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('2')
    expect(response.body).to include('a@example.org').and include('b@example.org')
    expect(payload_from(response.body)).to be_present
    expect(Submission.count).to eq(0)
  end

  it 'creates one submission per row on confirmation' do
    preview("email,name\na@example.org,A\nb@example.org,B\nc@example.org,C\n", send_email: '0')
    payload = payload_from(response.body)

    expect do
      post "/templates/#{template.id}/submissions_lists", params: { payload:, send_email: '0' }
    end.to change(Submission, :count).by(3)

    expect(response).to redirect_to(template_path(template))
    expect(Submitter.order(:id).pluck(:email)).to eq(['a@example.org', 'b@example.org', 'c@example.org'])
    expect(Submitter.order(:id).pluck(:name)).to eq(%w[A B C])
    expect(Submitter.all.map { |s| s.preferences['send_email'] }).to all(be(false))
  end

  it 'honours the send_email choice' do
    allow(Accounts).to receive(:can_send_emails?).and_return(true)

    preview("email\na@example.org\n", send_email: '1')

    post "/templates/#{template.id}/submissions_lists", params: { payload: payload_from(response.body),
                                                                  send_email: '1' }

    expect(Submitter.last.preferences['send_email']).to be(true)
  end

  it 'refuses the whole file when one row is wrong, and offers nothing to confirm' do
    expect { preview("email,name\na@example.org,A\nnot-an-email,B\n") }.not_to change(Submission, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('is not an e-mail address')
    expect(payload_from(response.body)).to be_nil
  end

  it 'sends the user back when the file cannot be read at all' do
    preview("name\nA\n")

    expect(response).to redirect_to(new_template_submission_path(template))
    expect(flash[:alert]).to eq('The first row must name an "email" column')
    expect(Submission.count).to eq(0)
  end

  # The rows travel in a signed payload, so what is confirmed is what was previewed.
  it 'creates nothing from a tampered payload' do
    preview("email\na@example.org\n")
    payload = payload_from(response.body)

    expect do
      post "/templates/#{template.id}/submissions_lists", params: { payload: "#{payload}x" }
    end.not_to change(Submission, :count)

    expect(response).to redirect_to(template_path(template))
    expect(flash[:alert]).to eq('This list is no longer available — upload the file again')
  end

  it 'creates nothing from a payload signed for another template' do
    other = create(:template, account:, author:, only_field_types: %w[text])

    preview("email\na@example.org\n")
    payload = payload_from(response.body)

    expect do
      post "/templates/#{other.id}/submissions_lists", params: { payload: }
    end.not_to change(Submission, :count)

    expect(flash[:alert]).to eq('This list is no longer available — upload the file again')
  end

  it 'refuses a viewer' do
    sign_in(create(:user, account:, role: 'viewer'))

    expect { preview("email\na@example.org\n") }.not_to change(Submission, :count)

    expect(response).to redirect_to(root_path)
  end

  it 'lets an editor send a list' do
    sign_in(create(:user, account:, role: 'editor'))

    preview("email\na@example.org\n")
    expect(response).to have_http_status(:ok)

    expect do
      post "/templates/#{template.id}/submissions_lists", params: { payload: payload_from(response.body) }
    end.to change(Submission, :count).by(1)
  end
end
