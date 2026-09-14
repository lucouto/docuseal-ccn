# frozen_string_literal: true

describe Ccn::Gotenberg do
  let(:base_url) { 'http://gotenberg.test:3000' }
  let(:pdf_bytes) { Rails.root.join('spec/fixtures/ccn/fieldtags.pdf').binread }

  # webmock/rspec is loaded by rails_helper: net connections are disabled and stubs reset after each example.
  before { stub_const('Ccn::GOTENBERG_URL', base_url) }

  describe '.docx_to_pdf' do
    it 'posts the file as multipart to the LibreOffice route and returns the PDF bytes' do
      stub = stub_request(:post, "#{base_url}/forms/libreoffice/convert")
             .with do |req|
               req.headers['Content-Type'].start_with?('multipart/form-data') &&
                 req.body.include?('filename="lease.docx"')
             end
             .to_return(status: 200, body: pdf_bytes, headers: { 'Content-Type' => 'application/pdf' })

      result = described_class.docx_to_pdf(StringIO.new('PK docx bytes'), 'lease.docx')

      expect(result).to eq(pdf_bytes)
      expect(stub).to have_been_requested
    end

    it 'raises Unavailable when the sidecar is not configured' do
      stub_const('Ccn::GOTENBERG_URL', nil)

      expect { described_class.docx_to_pdf(StringIO.new('x'), 'a.docx') }
        .to raise_error(Ccn::Gotenberg::Unavailable, /not configured/)
    end

    it 'raises Unavailable when the connection is refused' do
      stub_request(:post, "#{base_url}/forms/libreoffice/convert").to_raise(Errno::ECONNREFUSED)

      expect { described_class.docx_to_pdf(StringIO.new('x'), 'a.docx') }.to raise_error(Ccn::Gotenberg::Unavailable)
    end

    it 'raises TimedOut when the sidecar does not answer in time' do
      stub_request(:post, "#{base_url}/forms/libreoffice/convert").to_timeout

      expect { described_class.docx_to_pdf(StringIO.new('x'), 'a.docx') }.to raise_error(Ccn::Gotenberg::TimedOut)
    end

    it 'raises Rejected with the status when the sidecar refuses the document' do
      stub_request(:post, "#{base_url}/forms/libreoffice/convert").to_return(status: 500, body: 'LibreOffice failed')

      expect { described_class.docx_to_pdf(StringIO.new('x'), 'a.docx') }
        .to raise_error(Ccn::Gotenberg::Rejected) { |e| expect(e.status).to eq(500) }
    end
  end

  describe '.html_to_pdf' do
    it 'posts index.html with the paper size of the requested format and optional header/footer' do
      stub = stub_request(:post, "#{base_url}/forms/chromium/convert/html").with do |req|
        req.body.include?('filename="index.html"') && req.body.include?('<h1>Lease</h1>') &&
          req.body.include?('filename="header.html"') && req.body.include?('8.27') && req.body.include?('11.69')
      end.to_return(status: 200, body: pdf_bytes)

      result = described_class.html_to_pdf('<h1>Lease</h1>', header: '<p>Head</p>', size: 'A4')

      expect(result).to eq(pdf_bytes)
      expect(stub).to have_been_requested
    end

    it 'rejects an unknown page size before calling the sidecar' do
      expect { described_class.html_to_pdf('<p>x</p>', size: 'B5') }.to raise_error(ArgumentError, /unknown page size/)
    end
  end
end
