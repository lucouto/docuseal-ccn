# frozen_string_literal: true

module Api
  # CCN fork — the template ingestion operations upstream reserves for Pro (specs/001-documents-by-any-route,
  # FR-007): POST /api/templates/{pdf,docx,html,merge} and PUT /api/templates/:id/documents. Thin: params →
  # Ccn::* services → Templates::SerializeForApi. Not under an Api::Ccn namespace (it would shadow ::Ccn).
  class CcnTemplatesDocumentsController < ApiBaseController
    include Ccn::IngestionErrors

    load_and_authorize_resource :template, parent: false, only: :update

    before_action(only: %i[pdf docx html merge]) { authorize!(:create, Template) }

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
      templates = Ccn::MergeTemplates.find_templates(current_ability, params[:template_ids])
      template = Ccn::MergeTemplates.call(user: current_user, templates:, params:)

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
  end
end
