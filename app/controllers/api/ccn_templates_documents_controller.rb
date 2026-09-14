# frozen_string_literal: true

module Api
  # CCN fork — the template ingestion operations upstream reserves for Pro (specs/001-documents-by-any-route,
  # FR-007): POST /api/templates/{pdf,docx,html,merge} and PUT /api/templates/:id/documents. Thin: params →
  # Ccn::* services → Templates::SerializeForApi. Not under an Api::Ccn namespace (it would shadow ::Ccn).
  class CcnTemplatesDocumentsController < ApiBaseController
    load_and_authorize_resource :template, only: :update

    before_action(only: %i[pdf docx html merge]) { authorize!(:create, Template) }

    # Everything a client can cause is a 422 with a plain-language message (FR-015, plan design 8).
    rescue_from Ccn::Gotenberg::Error do |e|
      render_error(Ccn::OfficeDocument.error_message(e))
    end

    rescue_from Ccn::DocumentParams::Invalid, DownloadUtils::UnableToDownload do |e|
      render_error(e.message)
    end

    rescue_from Ccn::NotSupportedYet do |e|
      render_error(I18n.t('ccn_not_supported_yet', feature: e.message))
    end

    rescue_from Templates::CreateAttachments::PdfEncrypted do
      render_error(I18n.t('ccn_pdf_encrypted'))
    end

    rescue_from Templates::CreateAttachments::InvalidFileType do |e|
      render_error(invalid_file_type_message(e))
    end

    rescue_from Pdfium::PdfiumError do |e|
      render_error(I18n.t('ccn_invalid_document', message: e.message))
    end

    def pdf
      create_from(Ccn::DocumentParams.files_from(documents_params))
    end

    # Same pipeline as pdf: the file type decides; office documents need the conversion sidecar.
    def docx
      create_from(Ccn::DocumentParams.files_from(documents_params))
    end

    def html
      create_from(Ccn::HtmlDocuments.files_from(params), documents: [])
    end

    def merge
      template = Ccn::MergeTemplates.call(user: current_user, templates: merge_templates, params:)

      render json: Templates::SerializeForApi.call(template)
    end

    def update
      template = Ccn::UpdateTemplateDocuments.call(template: @template, params:)

      render json: Templates::SerializeForApi.call(template)
    end

    private

    def create_from(files, documents: documents_params)
      template = Ccn::CreateTemplateFromDocuments.call(user: current_user, params:, files:, documents:)

      render json: Templates::SerializeForApi.call(template)
    end

    def documents_params
      documents = Array.wrap(params[:documents])

      raise Ccn::DocumentParams::Invalid, 'documents[] is required' if documents.empty?

      documents
    end

    def merge_templates
      ids = Array.wrap(params[:template_ids]).map { |id| Integer(id.to_s, 10, exception: false) }.compact

      raise Ccn::DocumentParams::Invalid, 'template_ids[] is required' if ids.empty?

      templates = Template.accessible_by(current_ability).active.where(id: ids).index_by(&:id)
      missing = ids - templates.keys

      raise Ccn::DocumentParams::Invalid, I18n.t('ccn_template_not_found', id: missing.join(', ')) if missing.any?

      ids.map { |id| templates[id] }
    end

    # Templates::CreateAttachments raises "<content type>/<dynamic>" for a type it cannot ingest.
    def invalid_file_type_message(error)
      type = error.message.delete_suffix('/false').delete_suffix('/true')

      if Templates::CreateAttachments::DOCUMENT_CONTENT_TYPES.include?(type)
        return I18n.t('ccn_conversion_unavailable')
      end

      I18n.t('ccn_unsupported_file_type', type:)
    end

    def render_error(message)
      render json: { error: message }, status: :unprocessable_content
    end
  end
end
