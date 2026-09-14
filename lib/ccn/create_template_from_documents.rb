# frozen_string_literal: true

module Ccn
  # POST /api/templates/{pdf,docx,html} (specs/001-documents-by-any-route, US3, FR-007..FR-009): builds a
  # template from already-resolved files (Ccn::DocumentParams / Ccn::HtmlDocuments) and lets
  # Templates::CreateAttachments do what it does for the builder — conversion, text tags, AcroForm fields,
  # previews. `external_id` upserts (research D9); explicit `fields[]` win over detected fields with the same
  # name (FR-008). Webhooks and search reindex fire after the transaction, as in the upstream controllers.
  module CreateTemplateFromDocuments
    module_function

    # @param user [User] the API user, author of the template
    # @param params [ActionController::Parameters, Hash] request body: name, folder_name, external_id
    #   (or application_key), shared_link, remove_tags, flatten, dynamic
    # @param files [Array<ActionDispatch::Http::UploadedFile>] one per documents[] entry, same order
    # @param documents [Array] the raw documents[] entries (their `fields` are the explicit fields)
    # @param transient [Boolean] a throw-away template for a template-less submission (research D7): no
    #   external_id upsert, marked in preferences, no webhook and no search entry
    # @return [Template] saved and reloaded
    def call(user:, params:, files:, documents: [], transient: false)
      raise Ccn::NotSupportedYet, 'dynamic documents' if dynamic?(params, documents)
      raise Ccn::DocumentParams::Invalid, 'documents[] is required' if files.empty?

      external_id = params[:external_id].presence || params[:application_key].presence unless transient
      template = find_existing(user, external_id)
      event = template ? 'template.updated' : 'template.created'
      template ||= user.account.templates.new(author: user, source: :api, external_id:)
      template.preferences = template.preferences.merge('ccn_transient' => true) if transient

      build(template, user, params, files, documents, replace: event == 'template.updated')

      unless transient
        WebhookUrls.enqueue_events(template, event)
        SearchEntries.enqueue_reindex(template)
      end

      template.reload
    end

    # No transaction spans the conversions and uploads (upstream holds none there either): a failure while
    # creating destroys the new template, which purges its blobs; an upsert that fails leaves the existing
    # template's stored schema untouched (its in-memory changes are never saved).
    def build(template, user, params, files, documents, replace:)
      created = template.new_record?

      assign_attributes(template, user, params, files, template.external_id)
      template.save!

      attachments = attach(template, files, params, replace:)
      merge_explicit_fields(template, attachments, documents)

      template.save!
    rescue StandardError
      template.destroy if created && template.persisted?

      raise
    end

    def find_existing(user, external_id)
      return if external_id.blank?

      user.account.templates.active.find_by(external_id:)
    end

    def assign_attributes(template, user, params, files, external_id)
      template.name = params[:name].presence || template.name.presence ||
                      File.basename(files.first.original_filename.to_s, '.*')
      template.external_id = external_id if external_id
      template.shared_link = Ccn::DocumentParams.boolean(params[:shared_link]) if params.key?(:shared_link)

      if params[:folder_name].present? || template.new_record?
        template.folder = TemplateFolders.find_or_create_by_name(user, params[:folder_name])
      end

      Templates.maybe_assign_access(template)
    end

    # Create: every file becomes a schema item with its detected fields. Upsert: the new files replace the
    # existing documents position by position (Templates::ReplaceAttachments keeps the fields, re-pointed);
    # documents beyond the new count are dropped with their fields.
    def attach(template, files, params, replace:)
      attachment_params = { files:, remove_tags: params[:remove_tags], flatten: params[:flatten] }

      unless replace
        attachments, = Templates::CreateAttachments.call(template, attachment_params, extract_fields: true)

        template.schema = attachments.map { |a| { 'attachment_uuid' => a.uuid, 'name' => a.filename.base } }
        template.fields = Templates::ProcessDocument.normalize_attachment_fields(template, attachments)

        return attachments
      end

      attachments = Templates::ReplaceAttachments.call(template, attachment_params, extract_fields: true)

      # ReplaceAttachments writes symbol-keyed items in place; string keys are what everything downstream reads.
      template.schema = template.schema.map { |item| item.to_h.stringify_keys }
      dropped = template.schema.slice!(attachments.size..) || []
      dropped.each do |item|
        Ccn::UpdateTemplateDocuments.drop_document_fields(template.fields, item['attachment_uuid'])
      end

      attachments
    end

    def merge_explicit_fields(template, attachments, documents)
      explicit = Array.wrap(documents).each_with_index.flat_map do |document, index|
        fields = Ccn::DocumentParams.indifferent(document)[:fields]

        next [] if fields.blank? || attachments[index].nil?

        Ccn::DocumentParams.normalize_explicit_fields(fields, template, attachments[index].uuid)
      end

      return if explicit.empty?

      names = explicit.pluck('name')
      template.fields = template.fields.reject { |field| names.include?(field['name']) } + explicit
    end

    def dynamic?(params, documents)
      return true if Ccn::DocumentParams.boolean(params[:dynamic])

      Array.wrap(documents).any? do |document|
        Ccn::DocumentParams.boolean(Ccn::DocumentParams.indifferent(document)[:dynamic])
      end
    end
  end
end
