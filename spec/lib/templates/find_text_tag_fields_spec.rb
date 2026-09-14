# frozen_string_literal: true

describe Templates::FindTextTagFields do
  let(:data) { Rails.root.join('spec/fixtures/ccn/fieldtags.pdf').binread }
  let(:attachment_uuid) { SecureRandom.uuid }
  let(:result) { Pdfium::Document.open_io(StringIO.new(data)) { |doc| described_class.call(doc, attachment_uuid) } }
  let(:fields) { result.first }
  let(:redactions) { result.last }
  let(:by_name) { fields.index_by { |f| f['name'] } }
  # The fixture is A4 (HexaPDF's default page size); the detector normalizes by the real page box.
  let(:page_size) do
    Pdfium::Document.open_io(StringIO.new(data)) { |doc| [doc.get_page(1).width, doc.get_page(1).height] }
  end

  it 'finds the 8 documented fields with their types, roles and attributes' do
    expect(fields.pluck('name'))
      .to contain_exactly('Text Field', 'Field1', 'FIeld2', 'DOB', 'Signature', 'Sign here', 'Name', 'Test')
    expect(by_name['Text Field']).to include('type' => 'text', 'required' => true)
    expect(by_name['Text Field']).not_to have_key('role')
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

    expect(areas.pluck('page')).to eq([0, 1])
    expect(areas).to all(include('attachment_uuid' => attachment_uuid))
    expect(fields.pluck('uuid').uniq.size).to eq(fields.size)
  end

  it 'uses width and height in points for the field box, anchored at the tag' do
    area = by_name['Test']['areas'].first
    page_width, page_height = page_size

    expect(page_size.map(&:round)).to eq([595, 842])
    expect(area['w']).to be_within(0.001).of(200.0 / page_width)
    expect(area['h']).to be_within(0.001).of(30.0 / page_height)
    expect(area['page']).to eq(1)
    expect(area['x']).to be_between(0, 1)
  end

  it 'sizes an unsized tag by its own text box' do
    area = by_name['DOB']['areas'].first

    expect(area['w']).to be_between(0.05, 0.4)
    expect(area['h']).to be_between(0.005, 0.03)
  end

  it 'ignores an unclosed tag' do
    expect(fields.pluck('name').grep(/never closes/)).to be_empty
  end

  it 'returns one redaction rectangle per tag occurrence, per page' do
    expect(redactions.keys).to eq([0, 1])
    expect(redactions[0].size).to eq(6)
    expect(redactions[1].size).to eq(3)
    expect(redactions[0].first.keys).to contain_exactly('x', 'y', 'w', 'h', 'color')
    expect(redactions[0].first['color']).to eq('white') # erase only, no painted bar (Page#redact)
  end

  describe '.parse' do
    it 'reads the first segment as the name and the rest as attributes' do
      expect(described_class.parse('Foo')).to eq('name' => 'Foo')
      parsed = described_class.parse(' Foo ; Type=Date ; role=Tenant ')
      expect(parsed).to eq('name' => 'Foo', 'type' => 'Date', 'role' => 'Tenant')
      expect(described_class.parse('name=Foo;type=date')).to eq('name' => 'Foo', 'type' => 'date')
    end

    it 'rejects a tag without a name' do
      expect(described_class.parse(';type=date')).to be_nil
      expect(described_class.parse('type=signature;role=X')).to be_nil
      expect(described_class.parse('Foo=bar')).to be_nil
      expect(described_class.parse('')).to be_nil
    end
  end

  it 'does not let a stray opening brace swallow the tag that follows on the same line' do
    expect('a {{ b {{Real;type=date}} c'.scan(described_class::TAG_REGEXP).flatten).to eq(['Real;type=date'])
  end

  it 'erases every tag when the rectangles are redacted, keeping the surrounding text' do
    io = StringIO.new

    Pdfium::Document.open_io(StringIO.new(data)) do |doc|
      _fields, rects_by_page = described_class.call(doc, attachment_uuid)

      rects_by_page.each { |page_index, rects| doc.get_page(page_index).redact(rects) }

      doc.save(io)
    end

    Pdfium::Document.open_io(StringIO.new(io.string)) do |doc|
      texts = Array.new(doc.page_count) { |i| doc.get_page(i).text_nodes.map(&:content).join }

      expect(texts.join).not_to include('{{Text Field}}', '{{DOB', 'width=200')
      # Upstream's Page#redact rebuilds a partially redacted text object one glyph at a time and drops the
      # blank ones, so the extracted text of a redacted line loses its spaces (the rendering does not).
      expect(texts.first.delete(' ')).to include('Tenantname:', 'Dateofbirth:')
      expect(texts.last).to include('Prefilled')
    end
  end

  it 'returns nothing for a document without tags' do
    plain = Rails.root.join('spec/fixtures/sample-document.pdf').binread

    expect(Pdfium::Document.open_io(StringIO.new(plain)) { |doc| described_class.call(doc, attachment_uuid) })
      .to eq([[], {}])
  end
end
