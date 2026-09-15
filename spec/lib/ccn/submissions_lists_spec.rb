# frozen_string_literal: true

# CCN fork — Stage 4, US4 (specs/003-p1-features): reading a spreadsheet of signers.
describe Ccn::SubmissionsLists do
  let(:account) { create(:account) }
  let!(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, only_field_types: %w[text]) }
  let(:two_role_template) do
    create(:template, account:, author:, submitter_count: 2, only_field_types: %w[text])
  end

  def upload(content, filename = 'list.csv', content_type = 'text/csv')
    tempfile = Tempfile.new(['list', File.extname(filename)])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(tempfile:, filename:, type: content_type)
  end

  def xlsx_upload(rows)
    workbook = RubyXL::Workbook.new
    sheet = workbook[0]
    rows.each_with_index do |row, r|
      row.each_with_index { |value, c| sheet.add_cell(r, c, value) }
    end

    upload(workbook.stream.string, 'list.xlsx',
           'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
  end

  it 'reads a CSV into one submission per row' do
    result = described_class.parse(upload("email,name\na@example.org,A\nb@example.org,B\n"), template)

    expect(result['rows_count']).to eq(2)
    expect(result['errors']).to be_empty
    expect(result['columns']).to eq(%w[email name])
    expect(result['preview']).to eq([{ 'email' => 'a@example.org', 'name' => 'A' },
                                     { 'email' => 'b@example.org', 'name' => 'B' }])

    submitters = result['submissions_attrs'].pluck(:submitters)

    expect(submitters.map { |s| s.first[:email] }).to eq(['a@example.org', 'b@example.org'])
    expect(submitters.map { |s| s.first[:name] }).to eq(%w[A B])
    expect(submitters.map { |s| s.first[:uuid] }).to all(eq(template.submitters.first['uuid']))
  end

  it 'reads an XLSX the same way, first sheet only' do
    result = described_class.parse(xlsx_upload([%w[email name], %w[a@example.org A]]), template)

    expect(result['rows_count']).to eq(1)
    expect(result['errors']).to be_empty
    expect(result['submissions_attrs'].first[:submitters].first[:email]).to eq('a@example.org')
  end

  it 'ignores blank rows and trims cells' do
    result = described_class.parse(upload("email,name\n\n  a@example.org  ,  A  \n"), template)

    expect(result['rows_count']).to eq(1)
    expect(result['submissions_attrs'].first[:submitters].first).to include(email: 'a@example.org', name: 'A')
  end

  # The line number is read by somebody holding the file, so it counts the blank rows they can see.
  it 'reports the line the row is really on, blank rows included' do
    result = described_class.parse(upload("email\n\n\nnot-an-email\n"), template)

    expect(result['errors']).to eq([{ 'line' => 4, 'error' => '"not-an-email" is not an e-mail address' }])
  end

  it 'refuses a file without an email column' do
    expect { described_class.parse(upload("name,phone\nA,+33100000000\n"), template) }
      .to raise_error(described_class::Invalid, 'The first row must name an "email" column')
  end

  it 'refuses a file with no rows at all' do
    expect { described_class.parse(upload(''), template) }
      .to raise_error(described_class::Invalid, 'The file has no rows')
  end

  it 'refuses more than 500 rows' do
    rows = (1..501).map { |i| "signer#{i}@example.org" }.join("\n")

    expect { described_class.parse(upload("email\n#{rows}\n"), template) }
      .to raise_error(described_class::Invalid, 'The file has more than 500 rows')
  end

  it 'reports a bad address by line and refuses the whole file' do
    csv = "email,name\na@example.org,A\nnot-an-email,B\nc@example.org,C\n"

    result = described_class.parse(upload(csv), template)

    expect(result['rows_count']).to eq(3)
    expect(result['errors']).to eq([{ 'line' => 4, 'error' => '"not-an-email" is not an e-mail address' }])
    expect(result['submissions_attrs']).to be_empty
  end

  it 'reports a row with no address at all' do
    result = described_class.parse(upload("email,name\n,B\n"), template)

    expect(result['errors']).to eq([{ 'line' => 2, 'error' => 'No e-mail address on this row' }])
    expect(result['submissions_attrs']).to be_empty
  end

  it 'prefills a field named by a column' do
    field = template.fields.first
    template.update!(fields: template.fields.map do |f|
      f['uuid'] == field['uuid'] ? f.merge('prefillable' => true) : f
    end)

    result = described_class.parse(upload("email,#{field['name']}\na@example.org,Marie\n"), template.reload)

    expect(result['errors']).to be_empty
    expect(result['submissions_attrs'].first[:submitters].first[:values]).to eq(field['uuid'] => 'Marie')
    expect(result['preview'].first).to include(field['name'] => 'Marie')
  end

  it 'ignores a column that names nothing' do
    result = described_class.parse(upload("email,internal reference\na@example.org,XYZ\n"), template)

    expect(result['errors']).to be_empty
    expect(result['columns']).to eq(['email', 'internal reference'])
    expect(result['submissions_attrs'].first[:submitters].size).to eq(1)
  end

  context 'when the template has several signer roles' do
    it 'routes a role-prefixed column to that role' do
      first, second = two_role_template.submitters.pluck('name')

      csv = "#{first}: email,#{first}: name,#{second}: email\na@example.org,A,b@example.org\n"
      result = described_class.parse(upload(csv), two_role_template)

      expect(result['errors']).to be_empty

      submitters = result['submissions_attrs'].first[:submitters]

      expect(submitters.size).to eq(2)
      expect(submitters.pluck(:email)).to contain_exactly('a@example.org', 'b@example.org')
      expect(submitters.find { |s| s[:email] == 'a@example.org' }[:name]).to eq('A')
    end

    it 'reports every bad address on the row' do
      first, second = two_role_template.submitters.pluck('name')

      csv = "#{first}: email,#{second}: email\nnope,also-nope\n"
      result = described_class.parse(upload(csv), two_role_template)

      expect(result['errors'].pluck('line')).to eq([2, 2])
    end
  end
end
