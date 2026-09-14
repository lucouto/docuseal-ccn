# frozen_string_literal: true

module Ccn
  # Rescue table of the /api/ccn/... controllers (FR-008): everything a client can cause is a 422 with a
  # plain-language `error`, a missing or foreign record is a 404 with the same shape; nothing client-controlled
  # may produce a 500.
  module AdminErrors
    extend ActiveSupport::Concern

    included do
      rescue_from Ccn::AdminInvalid, Ccn::DocumentParams::Invalid do |e|
        render json: { error: e.message }, status: :unprocessable_content
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_content
      end

      rescue_from Ccn::NotSupportedYet do |e|
        render json: { error: I18n.t('ccn_not_supported_yet', feature: e.message) }, status: :unprocessable_content
      end

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: I18n.t('ccn_not_found') }, status: :not_found
      end
    end
  end
end
