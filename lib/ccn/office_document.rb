# frozen_string_literal: true

module Ccn
  # Office documents (docx, doc, odt, rtf, xlsx, xls) → PDF upload through the Gotenberg sidecar, so that
  # Templates::CreateAttachments can treat them exactly like an uploaded PDF (FORK-PLAN.md §5.2).
  module OfficeDocument
    PDF_CONTENT_TYPE = 'application/pdf'

    module_function

    def office?(file)
      ::Templates::CreateAttachments::DOCUMENT_CONTENT_TYPES.include?(file.content_type) ||
        ::Templates::CreateAttachments::DOCUMENT_EXTENSIONS.include?(File.extname(file.original_filename.to_s).downcase)
    end

    # @return [ActionDispatch::Http::UploadedFile] the converted PDF, named after the original file
    def convert(file)
      io = file.respond_to?(:tempfile) ? file.tempfile.tap(&:rewind) : StringIO.new(file.read)
      pdf = Ccn::Gotenberg.docx_to_pdf(io, file.original_filename)

      tempfile = Tempfile.new(['ccn-converted', '.pdf'])
      tempfile.binmode
      tempfile.write(pdf)
      tempfile.rewind

      ActionDispatch::Http::UploadedFile.new(
        tempfile:, filename: "#{File.basename(file.original_filename.to_s, '.*')}.pdf", type: PDF_CONTENT_TYPE
      )
    end

    def error_message(error)
      case error
      when Ccn::Gotenberg::TimedOut then I18n.t('ccn_conversion_timeout')
      when Ccn::Gotenberg::Rejected then I18n.t('ccn_conversion_rejected', status: error.status)
      else I18n.t('ccn_conversion_unavailable')
      end
    end
  end
end
