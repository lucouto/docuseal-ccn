# frozen_string_literal: true

# One-off generator for spec/fixtures/ccn/fieldtags.pdf (run once, output committed):
#   ruby spec/fixtures/ccn/build_fieldtags_pdf.rb > spec/fixtures/ccn/fieldtags.pdf
# The 8 tag examples of DocuSeal's field-tag syntax sheet (fieldtags.pdf), spread over two pages, plus a
# second {{Text Field}} on page 2 (same name and role → one field with two areas) and plain prose around
# them. Letter size, Helvetica 12 pt.
require 'hexapdf'
require 'stringio'

doc = HexaPDF::Document.new

def write_lines(page, lines)
  canvas = page.canvas
  canvas.font('Helvetica', size: 12)
  lines.each_with_index do |line, index|
    canvas.text(line, at: [72, 720 - (index * 36)])
  end
end

page1 = doc.pages.add
write_lines(page1, [
  'Lease agreement - field tag fixture (page 1)',
  'Tenant name: {{Text Field}}',
  'First party initials: {{Field1;role=First Party}}   Second party initials: {{FIeld2;role=Signer2}}',
  'Date of birth: {{DOB;type=date}}',
  'Signed: {{Signature}}',
  'Countersigned: {{Sign here;type=signature}}'
])

page2 = doc.pages.add
write_lines(page2, [
  'Lease agreement - field tag fixture (page 2)',
  'Prefilled: {{Name;readonly=true;default=Bob}}',
  'Photo: {{Test;readonly=false;required=false;type=image;role=Signer2;width=200;height=30}}',
  'Tenant name again: {{Text Field}}',
  'This line has no tag and a stray {{ that never closes.'
])

io = StringIO.new
doc.write(io)
$stdout.binmode
$stdout.write(io.string)
