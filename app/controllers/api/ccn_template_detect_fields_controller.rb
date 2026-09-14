# frozen_string_literal: true

module Api
  # CCN fork — POST /api/ccn/templates/{id}/detect_fields (specs/002-everything-by-api, US4). Thin over
  # Ccn::DetectTemplateFields; the ML detector itself is upstream's Templates::DetectFields.
  class CcnTemplateDetectFieldsController < ApiBaseController
    include Ccn::AdminErrors
    include Ccn::IngestionErrors # the detector's own failures (corrupt/encrypted PDF, bad image) are 422s too

    def create
      template = Template.accessible_by(current_ability).find(params[:template_id])

      authorize!(:update, template)

      render json: Ccn::DetectTemplateFields.call(template, attachment_uuid: params[:attachment_uuid],
                                                            page: params[:page],
                                                            apply: Ccn::DocumentParams.boolean(params[:apply]))
    end
  end
end
