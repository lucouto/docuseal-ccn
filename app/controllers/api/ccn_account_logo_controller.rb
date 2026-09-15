# frozen_string_literal: true

module Api
  # CCN fork — Stage 4, US2 (specs/003-p1-features): GET/PUT/DELETE /api/ccn/account_logo. The UI twin is
  # CcnAccountLogosController; both attach through Ccn::AccountLogo's validation, this one reporting a
  # refusal as the 422 every other /api/ccn/... operation uses.
  class CcnAccountLogoController < ApiBaseController
    include Ccn::AdminErrors

    before_action { authorize!(:manage, current_account) }

    def show
      raise ActiveRecord::RecordNotFound unless current_account.logo.attached?

      render json: serialize(current_account.logo)
    end

    def update
      current_account.logo.attach(uploaded_file)

      raise ActiveRecord::RecordInvalid, current_account if current_account.errors.any?

      render json: serialize(current_account.reload.logo)
    end

    def destroy
      current_account.logo.purge

      render json: { deleted: true }
    end

    private

    # `file` is base64, a data URI or an https URL, as the ingestion endpoints accept it; a multipart upload
    # (curl -F file=@logo.png) is taken as it comes.
    def uploaded_file
      file = params[:file]

      return file if file.respond_to?(:tempfile)

      Ccn::DocumentParams.file_from(file, param: 'file', name: params[:name])
    end

    def serialize(logo)
      {
        url: ActiveStorage::Blob.proxy_url(logo.blob),
        filename: logo.filename.to_s,
        content_type: logo.content_type,
        byte_size: logo.byte_size
      }
    end
  end
end
