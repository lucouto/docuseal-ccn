# frozen_string_literal: true

module Ccn
  # One rescue table for the document ingestion API controllers (plan design 8, FR-015): everything a client
  # can cause is a 422 with a plain-language `error`; nothing client-controlled may produce a 500. The MCP
  # tools reuse the class list and `message_for` (Ccn::McpToolErrors) so both surfaces answer alike.
  module IngestionErrors
    extend ActiveSupport::Concern

    # The archive class is named, not referenced: rubyzip reaches the bundle through rubyXL only, and upstream
    # too resolves Zip lazily.
    CLIENT_ERRORS = [Ccn::Gotenberg::Error, Ccn::DocumentParams::Invalid, DownloadUtils::UnableToDownload,
                     Submitters::NormalizeValues::BaseError, Submissions::CreateFromSubmitters::BaseError,
                     Ccn::NotSupportedYet, Templates::CreateAttachments::PdfEncrypted,
                     Templates::CreateAttachments::InvalidFileType, Pdfium::PdfiumError, Vips::Error,
                     'Zip::Error'].freeze

    included do
      rescue_from(*CLIENT_ERRORS) do |e|
        render json: { error: Ccn::IngestionErrors.message_for(e) }, status: :unprocessable_content
      end
    end

    # The translated message for any error of CLIENT_ERRORS.
    def self.message_for(error)
      case error
      when Ccn::Gotenberg::Error then Ccn::OfficeDocument.error_message(error)
      when Ccn::NotSupportedYet then I18n.t('ccn_not_supported_yet', feature: error.message)
      when Templates::CreateAttachments::PdfEncrypted then I18n.t('ccn_pdf_encrypted')
      when Templates::CreateAttachments::InvalidFileType then invalid_file_type_message(error)
      when Pdfium::PdfiumError then I18n.t('ccn_invalid_document', message: error.message)
      when Vips::Error then I18n.t('ccn_invalid_image')
      else
        error.class.name == 'Zip::Error' ? I18n.t('ccn_invalid_archive') : error.message
      end
    end

    # Templates::CreateAttachments raises "<content type>/<dynamic>" for a type it cannot ingest.
    def self.invalid_file_type_message(error)
      type = error.message.delete_suffix('/false').delete_suffix('/true')

      return I18n.t('ccn_zip_too_large') if type == 'zip_too_large'
      return I18n.t('ccn_unrecognized_file') if type == 'application/octet-stream'
      return I18n.t('ccn_conversion_unavailable') if Templates::CreateAttachments::DOCUMENT_CONTENT_TYPES.include?(type)

      I18n.t('ccn_unsupported_file_type', type:)
    end
  end
end
