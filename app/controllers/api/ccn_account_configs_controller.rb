# frozen_string_literal: true

module Api
  # CCN fork — /api/ccn/account_configs (specs/002-everything-by-api, US3). Thin over
  # Ccn::ManageAccountConfigs, whose typed allow-list keeps EncryptedConfig out by construction.
  class CcnAccountConfigsController < ApiBaseController
    include Ccn::AdminErrors

    before_action { authorize!(:manage, AccountConfig) }

    def index
      render json: { data: Ccn::ManageAccountConfigs.list(current_account) }
    end

    def show
      render json: Ccn::ManageAccountConfigs.get(current_account, params[:key])
    end

    def update
      value = params.key?(:value) ? params.to_unsafe_h['value'] : nil

      render json: Ccn::ManageAccountConfigs.set(current_account, params[:key], value)
    end

    def destroy
      render json: Ccn::ManageAccountConfigs.reset(current_account, params[:key])
    end
  end
end
