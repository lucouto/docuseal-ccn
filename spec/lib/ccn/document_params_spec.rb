# frozen_string_literal: true

describe Ccn::DocumentParams do
  let(:pdf_bytes) { Rails.root.join('spec/fixtures/ccn/fieldtags.pdf').binread }
  let(:pdf_base64) { Base64.strict_encode64(pdf_bytes) }

  describe '.files_from' do
    it 'decodes base64 documents into PDF uploads named after the document' do
      files = described_class.files_from([{ 'name' => 'Lease', 'file' => pdf_base64 }])

      expect(files.size).to eq(1)
      expect(files.first).to be_a(ActionDispatch::Http::UploadedFile)
      expect(files.first.content_type).to eq('application/pdf')
      expect(files.first.original_filename).to eq('Lease.pdf')
      expect(files.first.read).to eq(pdf_bytes)
    end

    it 'accepts a data URI prefix and line-wrapped base64' do
      wrapped = "data:application/pdf;base64,#{pdf_base64.scan(/.{1,76}/).join("\n")}"

      expect(described_class.files_from([{ file: wrapped }]).first.read).to eq(pdf_bytes)
    end

    it 'downloads https URLs and keeps the remote filename' do
      stub_request(:get, 'https://files.example.com/docs/lease%20v2.pdf').to_return(status: 200, body: pdf_bytes)

      file = described_class.files_from([{ file: 'https://files.example.com/docs/lease%20v2.pdf' }]).first

      expect(file.original_filename).to eq('lease v2.pdf')
      expect(file.content_type).to eq('application/pdf')
    end

    it 'refuses plain http URLs through DownloadUtils' do
      expect { described_class.files_from([{ file: 'http://files.example.com/lease.pdf' }]) }
        .to raise_error(DownloadUtils::UnableToDownload)
    end

    it 'raises Invalid for a missing or undecodable file' do
      expect { described_class.files_from([{ name: 'x' }]) }
        .to raise_error(described_class::Invalid, /\[file\] is required/)
      expect { described_class.files_from([{ file: '%%%not base64%%%' }]) }
        .to raise_error(described_class::Invalid, /not valid base64/)
    end
  end

  describe '.normalize_explicit_fields' do
    let(:template) { build(:template, submitters: [{ 'name' => 'First Party', 'uuid' => SecureRandom.uuid }]) }
    let(:attachment_uuid) { SecureRandom.uuid }
    let(:fields) do
      [
        { name: 'Amount', type: 'number', role: 'Tenant', required: false,
          areas: [{ x: 0.1, y: 0.2, w: 0.3, h: 0.05, page: 2 }] },
        { name: 'Plan', type: 'radio', options: %w[Basic],
          areas: [{ x: 0.1, y: 0.3, w: 0.05, h: 0.05, page: 1, option: 'Basic' },
                  { x: 0.2, y: 0.3, w: 0.05, h: 0.05, page: 1, option: 'Plus' }] }
      ]
    end
    let(:result) { described_class.normalize_explicit_fields(fields, template, attachment_uuid) }

    it 'converts 1-based pages to the stored 0-based index and stamps the attachment uuid' do
      area = result.first['areas'].first

      expect(area).to include('page' => 1, 'x' => 0.1, 'w' => 0.3, 'attachment_uuid' => attachment_uuid)
    end

    it 'creates a submitter for a new role and reuses the first one when no role is given' do
      expect(result.first['submitter_uuid']).to eq(template.submitters.last['uuid'])
      expect(template.submitters.pluck('name')).to eq(['First Party', 'Tenant'])
      expect(result.last['submitter_uuid']).to eq(template.submitters.first['uuid'])
    end

    it 'maps area options onto option uuids, creating options on the fly' do
      plan = result.last

      expect(plan['options'].pluck('value')).to eq(%w[Basic Plus])
      expect(plan['areas'].pluck('option_uuid')).to eq(plan['options'].pluck('uuid'))
    end

    it 'defaults required to true and omits readonly unless set' do
      expect(result.first).to include('required' => false)
      expect(result.last).to include('required' => true)
      expect(result.last).not_to have_key('readonly')
    end

    it 'rejects unsupported types and pages below 1' do
      expect { described_class.normalize_explicit_fields([{ name: 'x', type: 'payment' }], template, attachment_uuid) }
        .to raise_error(described_class::Invalid, /not supported/)
      expect do
        described_class.normalize_explicit_fields([{ name: 'x', areas: [{ page: 0 }] }], template, attachment_uuid)
      end.to raise_error(described_class::Invalid, /starting from 1/)
    end
  end

  describe '.strict_boolean' do
    it 'accepts the usual spellings of both values, in either case' do
      [true, 'true', 'TRUE', ' t ', '1', 'yes', 'on'].each do |value|
        expect(described_class.strict_boolean(value, 'dry_run')).to be(true)
      end

      [false, 'false', 'FALSE', 'f', '0', 'no', 'off'].each do |value|
        expect(described_class.strict_boolean(value, 'dry_run')).to be(false)
      end
    end

    it 'falls back to the default when the flag is absent' do
      expect(described_class.strict_boolean(nil, 'dry_run')).to be(false)
      expect(described_class.strict_boolean('', 'dry_run')).to be(false)
      expect(described_class.strict_boolean(nil, 'dry_run', default: true)).to be(true)
    end

    it 'refuses a value it cannot read rather than guessing a mode' do
      ['banana', 'truthy', '2', 'off!'].each do |value|
        expect { described_class.strict_boolean(value, 'dry_run') }
          .to raise_error(described_class::Invalid, /dry_run must be true or false/)
      end
    end

    it 'differs from the loose cast, which reads any non-empty string as true' do
      expect(described_class.boolean('banana')).to be(true)
      expect { described_class.strict_boolean('banana', 'dry_run') }.to raise_error(described_class::Invalid)
    end
  end
end
