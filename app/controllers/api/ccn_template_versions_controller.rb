# frozen_string_literal: true

module Api
  # CCN fork — /api/ccn/templates/{template_id}/versions (specs/002-everything-by-api, US4): the UI's
  # TemplatesVersionsController over the API, plus a server-side restore (Ccn::TemplateVersionRestore).
  class CcnTemplateVersionsController < ApiBaseController
    include Ccn::AdminErrors

    before_action :load_template
    before_action :load_version, only: %i[show restore]

    def index
      authorize!(:read, @template)

      versions = paginate(@template.template_versions.preload(:author))

      render json: {
        data: versions.as_json(TemplateVersions::SERIALIZE_PARAMS),
        pagination: { count: versions.size, next: versions.last&.id, prev: versions.first&.id }
      }
    end

    def show
      authorize!(:read, @template)

      render json: TemplateVersions.serialize(@version)
    end

    def create
      authorize!(:update, @template)

      version = TemplateVersions.find_or_create_for(@template, author: current_user)

      render json: version.as_json(TemplateVersions::SERIALIZE_PARAMS)
    end

    def restore
      authorize!(:update, @template)

      Ccn::TemplateVersionRestore.call(@template, @version, author: current_user)

      render json: Templates::SerializeForApi.call(@template.reload)
    end

    private

    def load_template
      @template = Template.accessible_by(current_ability).find(params[:template_id])
    end

    def load_version
      @version = @template.template_versions.find(params[:id])
    end
  end
end
