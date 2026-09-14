# frozen_string_literal: true

module Api
  # CCN fork — /api/ccn/template_folders (specs/002-everything-by-api, US4). Thin over Ccn::ManageFolders.
  class CcnTemplateFoldersController < ApiBaseController
    include Ccn::AdminErrors

    before_action { authorize!(:manage, TemplateFolder) }
    before_action :load_folder, only: %i[update destroy]

    def index
      folders = paginate(Ccn::ManageFolders.list(current_account))

      render json: {
        data: Ccn::ManageFolders.serialize_all(folders),
        pagination: { count: folders.size, next: folders.last&.id, prev: folders.first&.id }
      }
    end

    def create
      render json: Ccn::ManageFolders.create(current_user, folder_name)
    end

    def update
      render json: Ccn::ManageFolders.rename(@folder, folder_name)
    end

    def destroy
      render json: Ccn::ManageFolders.archive(@folder)
    end

    private

    def load_folder
      @folder = current_account.template_folders.find(params[:id])

      authorize!(:manage, @folder)
    end

    def folder_name
      params[:name] || params.dig(:template_folder, :name)
    end
  end
end
