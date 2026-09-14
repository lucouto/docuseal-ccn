# frozen_string_literal: true

module Ccn
  # One rescue table for the document ingestion API controllers (plan design 8, FR-015): everything a client
  # can cause is a 422 with a plain-language `error`; nothing client-controlled may produce a 500.
  module IngestionErrors
    extend ActiveSupport::Concern

    included do
      rescue_from Ccn::Gotenberg::Error do |e|
        render_ccn_error(Ccn::OfficeDocument.error_message(e))
      end

      rescue_from Ccn::DocumentParams::Invalid, DownloadUtils::UnableToDownload,
                  Submitters::NormalizeValues::BaseError, Submissions::CreateFromSubmitters::BaseError do |e|
        render_ccn_error(e.message)
      end

      # A client-supplied documents[].file URL that is unreachable, slow, malformed or not a URL at all.
      rescue_from Faraday::Error, URI::InvalidURIError, Addressable::URI::InvalidURIError do |e|
        render_ccn_error(I18n.t('ccn_download_failed', message: e.class.name.demodulize.underscore.humanize.downcase))
      end

      # A corrupt archive or image inside documents[].file.
      rescue_from Zip::Error, Vips::Error do |e|
        render_ccn_error(I18n.t('ccn_invalid_document', message: e.message.to_s.truncate(120)))
      end

      rescue_from Ccn::NotSupportedYet do |e|
        render_ccn_error(I18n.t('ccn_not_supported_yet', feature: e.message))
      end

      rescue_from Templates::CreateAttachments::PdfEncrypted do
        render_ccn_error(I18n.t('ccn_pdf_encrypted'))
      end

      rescue_from Templates::CreateAttachments::InvalidFileType do |e|
        render_ccn_error(ccn_invalid_file_type_message(e))
      end

      rescue_from Pdfium::PdfiumError do |e|
        render_ccn_error(I18n.t('ccn_invalid_document', message: e.message))
      end
    end

    private

    # Templates::CreateAttachments raises "<content type>/<dynamic>" for a type it cannot ingest.
    def ccn_invalid_file_type_message(error)
      type = error.message.delete_suffix('/false').delete_suffix('/true')

      return I18n.t('ccn_invalid_document', message: 'zip archive too large') if type == 'zip_too_large'
      return I18n.t('ccn_unrecognized_file') if type == 'application/octet-stream'
      return I18n.t('ccn_conversion_unavailable') if Templates::CreateAttachments::DOCUMENT_CONTENT_TYPES.include?(type)

      I18n.t('ccn_unsupported_file_type', type:)
    end

    def render_ccn_error(message)
      render json: { error: message }, status: :unprocessable_content
    end
  end
end
