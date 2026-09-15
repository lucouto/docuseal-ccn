# frozen_string_literal: true

# CCN fork — Stage 4, US2 (specs/003-p1-features): what may become an account logo.
describe Ccn::AccountLogo do
  let(:account) { create(:account) }

  # The validation reads magic bytes, never the filename, so a header is all a JPEG or WebP fixture needs.
  let(:png_bytes) { Rails.root.join('spec/fixtures/sample-image.png').binread }
  let(:jpeg_bytes) { ['FFD8FFE000104A46494600010100000100010000FFDB004300FFD9'].pack('H*') }
  let(:webp_bytes) { "RIFF#{[30].pack('V')}WEBPVP8 #{"\x00" * 22}".b }
  let(:gif_bytes) { "GIF89a#{"\x00" * 20}".b }
  let(:svg_bytes) { '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>' }

  def upload(bytes, filename, content_type)
    tempfile = Tempfile.new(['logo', File.extname(filename)])
    tempfile.binmode
    tempfile.write(bytes)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(tempfile:, filename:, type: content_type)
  end

  def attach(bytes, filename, content_type)
    account.logo.attach(upload(bytes, filename, content_type))
    account
  end

  it 'accepts a PNG' do
    attach(png_bytes, 'logo.png', 'image/png')

    expect(account.errors).to be_empty
    expect(account.reload.logo).to be_attached
    expect(account.logo.blob.content_type).to eq('image/png')
  end

  it 'accepts a JPEG' do
    attach(jpeg_bytes, 'logo.jpg', 'image/jpeg')

    expect(account.errors).to be_empty
    expect(account.reload.logo).to be_attached
  end

  it 'accepts a WebP' do
    attach(webp_bytes, 'logo.webp', 'image/webp')

    expect(account.errors).to be_empty
    expect(account.reload.logo).to be_attached
  end

  it 'refuses a logo over 2 MB and stores nothing' do
    oversize = png_bytes + ("\x00" * (2.megabytes + 1))

    attach(oversize, 'logo.png', 'image/png')

    expect(account.errors.full_messages).to eq(['The logo must be at most 2 MB'])
    expect(account.reload.logo).not_to be_attached
  end

  it 'refuses an SVG declared as such' do
    attach(svg_bytes, 'logo.svg', 'image/svg+xml')

    expect(account.errors.full_messages).to eq(['The logo must be a PNG, JPEG or WebP image'])
    expect(account.reload.logo).not_to be_attached
  end

  it 'refuses an SVG renamed and declared as a PNG (magic bytes, not the name, decide)' do
    attach(svg_bytes, 'logo.png', 'image/png')

    expect(account.errors.full_messages).to eq(['The logo must be a PNG, JPEG or WebP image'])
    expect(account.reload.logo).not_to be_attached
  end

  it 'refuses an image type outside the three accepted ones' do
    attach(gif_bytes, 'logo.gif', 'image/gif')

    expect(account.errors.full_messages).to eq(['The logo must be a PNG, JPEG or WebP image'])
    expect(account.reload.logo).not_to be_attached
  end

  it 'refuses a PNG whose declared type is something else' do
    attach(png_bytes, 'logo.png', 'application/pdf')

    expect(account.errors.full_messages).to eq(['The logo must be a PNG, JPEG or WebP image'])
    expect(account.reload.logo).not_to be_attached
  end

  it 'leaves the uploaded bytes readable for storage after reading the magic bytes' do
    attach(png_bytes, 'logo.png', 'image/png')

    expect(account.reload.logo.download).to eq(png_bytes)
  end

  it 'allows removing the logo, and other saves once one is stored' do
    attach(png_bytes, 'logo.png', 'image/png')

    expect(account.update(name: 'Chemin Neuf')).to be(true)

    account.logo.purge

    expect(account.reload.logo).not_to be_attached
  end

  it 'translates the refusal' do
    I18n.with_locale(:fr) { attach(svg_bytes, 'logo.svg', 'image/svg+xml') }

    expect(account.errors.full_messages).to eq(['Le logo doit être une image PNG, JPEG ou WebP'])
  end
end
