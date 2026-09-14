# frozen_string_literal: true

class TemplateDocumentsController < ApplicationController
  load_and_authorize_resource :template

  FILES_TTL = 5.minutes

  def index
    render json: @template.schema_documents.map { |d| ActiveStorage::Blob.proxy_path(d.blob, expires_at: FILES_TTL.from_now.to_i) }
  end

  def create
    authorize!(:update, @template)

    if params[:blobs].blank? && params[:files].blank?
      return render json: { error: I18n.t('file_is_missing') }, status: :unprocessable_content
    end

    old_fields_hash = @template.fields.hash
    old_submitters = @template.submitters.deep_dup # CCN: tag roles may add submitters (Ccn::AssignRoles)

    documents, = Templates::CreateAttachments.call(@template, params, extract_fields: true)

    submitters_changed = @template.submitters != old_submitters # CCN
    @template.save! if submitters_changed # CCN

    schema = documents.map do |doc|
      { attachment_uuid: doc.uuid, name: doc.filename.base }
    end

    render json: {
      schema:,
      fields: old_fields_hash == @template.fields.hash ? nil : @template.fields,
      submitters: old_fields_hash == @template.fields.hash && !submitters_changed ? nil : @template.submitters,
      documents: documents.as_json(
        methods: %i[metadata signed_key],
        include: {
          preview_images: { methods: %i[url metadata filename] }
        }
      )
    }
  rescue Templates::CreateAttachments::PdfEncrypted
    render json: { error: 'PDF encrypted', status: 'pdf_encrypted' }, status: :unprocessable_content
  end
end
