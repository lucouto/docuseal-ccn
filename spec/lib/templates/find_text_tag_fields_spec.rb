# frozen_string_literal: true

describe Templates::FindTextTagFields do
  let(:data) { Rails.root.join('spec/fixtures/ccn/fieldtags.pdf').binread }
  let(:attachment_uuid) { SecureRandom.uuid }
  let(:result) { Pdfium::Document.open_io(StringIO.new(data)) { |doc| described_class.call(doc, attachment_uuid) } }
  let(:fields) { result.first }
  let(:redactions) { result.last }
  let(:by_name) { fields.index_by { |f| f['name'] } }

  it 'finds the 8 documented fields with their types, roles and attributes' do
    expect(fields.map { |f| f['name'] })
      .to contain_exactly('Text Field', 'Field1', 'FIeld2', 'DOB', 'Signature', 'Sign here', 'Name', 'Test')
    expect(by_name['Text Field']).to include('type' => 'text', 'required' => true, 'role' => nil)
    expect(by_name['Field1']).to include('type' => 'text', 'role' => 'First Party')
    expect(by_name['FIeld2']).to include('role' => 'Signer2')
    expect(by_name['DOB']).to include('type' => 'date')
    expect(by_name['Signature']).to include('type' => 'signature')
    expect(by_name['Sign here']).to include('type' => 'signature')
    expect(by_name['Name']).to include('type' => 'text', 'readonly' => true, 'default_value' => 'Bob')
    expect(by_name['Test']).to include('type' => 'image', 'required' => false, 'role' => 'Signer2')
    expect(by_name['Test']).not_to have_key('readonly')
  end

  it 'merges repeated tags with the same name and role into one field with several areas' do
    areas = by_name['Text Field']['areas']

    expect(areas.map { |a| a['page'] }).to eq([0, 1])
    expect(areas).to all(include('attachment_uuid' => attachment_uuid))
    expect(fields.map { |f| f['uuid'] }.uniq.size).to eq(fields.size)
  end

  it 'uses width and height in points for the field box, anchored at the tag' do
    area = by_name['Test']['areas'].first

    expect(area['w']).to be_within(0.001).of(200.0 / 612)
    expect(area['h']).to be_within(0.001).of(30.0 / 792)
    expect(area['page']).to eq(1)
    expect(area['x']).to be_between(0, 1)
  end

  it 'sizes an unsized tag by its own text box' do
    area = by_name['DOB']['areas'].first

    expect(area['w']).to be_between(0.05, 0.4)
    expect(area['h']).to be_between(0.005, 0.03)
  end

  it 'ignores an unclosed tag' do
    expect(fields.map { |f| f['name'] }.grep(/never closes/)).to be_empty
  end

  it 'returns one redaction rectangle per tag occurrence, per page' do
    expect(redactions.keys).to eq([0, 1])
    expect(redactions[0].size).to eq(6)
    expect(redactions[1].size).to eq(3)
    expect(redactions[0].first.keys).to contain_exactly('x', 'y', 'w', 'h')
  end

  it 'erases every tag when the rectangles are redacted, keeping the surrounding text' do
    io = StringIO.new

    Pdfium::Document.open_io(StringIO.new(data)) do |doc|
      _fields, rects_by_page = described_class.call(doc, attachment_uuid)

      rects_by_page.each { |page_index, rects| doc.get_page(page_index).redact(rects) }

      doc.save(io)
    end

    Pdfium::Document.open_io(StringIO.new(io.string)) do |doc|
      texts = doc.page_count.times.map { |i| doc.get_page(i).text_nodes.map(&:content).join }

      expect(texts.join).not_to include('{{Text Field}}', '{{DOB', 'width=200')
      expect(texts.first).to include('Tenant name')
      expect(texts.last).to include('Prefilled')
    end
  end

  it 'returns nothing for a document without tags' do
    plain = Rails.root.join('spec/fixtures/sample-document.pdf').binread

    expect(Pdfium::Document.open_io(StringIO.new(plain)) { |doc| described_class.call(doc, attachment_uuid) })
      .to eq([[], {}])
  end
end
