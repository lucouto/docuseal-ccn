# frozen_string_literal: true

module Ccn
  # Orchestrates text-tag extraction for one PDF inside Templates::CreateAttachments#handle_pdf_or_image:
  # Templates::FindTextTagFields, then the AcroForm fields (both before the redaction, which flattens the
  # widgets), then the tags are erased with Page#redact and the document saved — the stored blob is the
  # redacted PDF. Note: Page#redact rebuilds a partially erased text run glyph by glyph and drops the blank
  # glyphs, so text extracted from an erased line has no spaces (the rendering is unchanged).
  module TextTags
    Result = Struct.new(:fields, :data, :doc)
    AttachmentStub = Struct.new(:uuid)

    module_function

    # @return [Result, nil] nil when nothing applies (no extraction, document too large, no tags)
    def call(doc, data, attachment_uuid, params, extract_fields:)
      return unless extract_fields && data.size < ::Templates::ProcessDocument::MAX_FLATTEN_FILE_SIZE

      tag_fields, redactions = detect(doc, attachment_uuid)

      return if tag_fields.blank?

      acro_fields = ::Templates::FindPdfiumAcroFields.call(AttachmentStub.new(attachment_uuid), doc, data)
      fields = acro_fields.map(&:deep_stringify_keys) + tag_fields

      return Result.new(fields:, data:, doc:) unless remove_tags?(params)

      redacted = redact(doc, redactions)

      Result.new(fields:, data: redacted, doc: Pdfium::Document.open_bytes(redacted))
    end

    def remove_tags?(params)
      !params[:remove_tags].to_s.casecmp?('false')
    end

    # Detection must never turn a working upload into a 500: on any failure the document takes the upstream
    # path untouched (the stance of Templates::BuildPdfiumAnnotations).
    def detect(doc, attachment_uuid)
      ::Templates::FindTextTagFields.call(doc, attachment_uuid)
    rescue StandardError => e
      Rollbar.error(e) if defined?(Rollbar)
      Rails.logger.error("CCN text tags skipped: #{e.class}: #{e.message}")

      [[], {}]
    end

    # Erases the rectangles page by page, saves the document and closes the original handle. The handle of a
    # password-protected upload still carries its security handler after decrypt_document, hence the flag.
    def redact(doc, redactions)
      redactions.each { |page_index, rects| doc.get_page(page_index).redact(rects) }

      io = StringIO.new
      doc.save(io, flags: Pdfium::FPDF_REMOVE_SECURITY)
      doc.close

      io.string
    end

    # Fields carry a transient 'role'; map it onto template.submitters and store them where
    # Templates::ProcessDocument.normalize_attachment_fields picks them up.
    def store_fields(template, document, fields)
      Ccn::AssignRoles.call(template, fields)

      document.metadata['pdf'] ||= {}
      document.metadata['pdf']['fields'] = fields

      document
    end
  end
end
