# frozen_string_literal: true

module Ccn
  # POST /api/templates/merge (FR-010, plan design 6): a new template holding the documents of the given
  # templates in order — blobs shared as Templates::Clone does, preview images cloned, fields and schema
  # deep-copied with fresh uuids (Templates::Clone's remapping keeps conditions and formulas consistent),
  # roles mapped positionally onto `roles` when given, otherwise matched by name. Sources are untouched.
  module MergeTemplates
    module_function

    # The templates named by `template_ids`, in that order, all readable by the caller and active; used by the
    # REST operation and the MCP tool alike.
    def find_templates(ability, template_ids)
      ids = Array.wrap(template_ids).filter_map { |id| Integer(id.to_s, 10, exception: false) }

      raise Ccn::DocumentParams::Invalid, 'template_ids[] is required' if ids.empty?

      templates = Template.accessible_by(ability).active.where(id: ids).index_by(&:id)
      missing = ids - templates.keys

      raise Ccn::DocumentParams::Invalid, I18n.t('ccn_template_not_found', id: missing.join(', ')) if missing.any?

      ids.map { |id| templates[id] }
    end

    def call(user:, templates:, params:)
      roles = Array.wrap(params[:roles]).map { |role| role.to_s.squish }.compact_blank
      template = build_template(user, templates, params, roles)

      templates.each { |source| append(template, source, roles) }

      if template.submitters.empty?
        template.submitters = [{ 'name' => I18n.t(:first_party), 'uuid' => SecureRandom.uuid }]
      end

      Templates.maybe_assign_access(template)
      template.save!

      WebhookUrls.enqueue_events(template, 'template.created')
      SearchEntries.enqueue_reindex(template)

      template.reload
    end

    def build_template(user, templates, params, roles)
      template = user.account.templates.new(author: user, source: :api)
      template.name = params[:name].presence || "#{templates.first.name} (Merged)"
      template.external_id = params[:external_id].presence || params[:application_key].presence
      template.folder = TemplateFolders.find_or_create_by_name(user, params[:folder_name])
      template.shared_link = Ccn::DocumentParams.boolean(params[:shared_link]) if params.key?(:shared_link)
      template.submitters = roles.map { |name| { 'name' => name, 'uuid' => SecureRandom.uuid } }
      template.schema = []
      template.fields = []

      template
    end

    def append(template, source, roles)
      raise Ccn::NotSupportedYet, 'dynamic documents' if source.schema.any? { |item| item['dynamic'] }

      # The remapped preferences (4th value) are dropped on purpose: template preferences are per template and
      # merging N of them has no defined meaning; the merged template starts with the defaults.
      submitters, fields, schema, = Templates::Clone.update_submitters_and_fields_and_schema(
        source.submitters.deep_dup, source.fields.deep_dup, source.schema.deep_dup, source.preferences.deep_dup
      )

      submitter_map = map_submitters(template, submitters, roles)
      attachment_map = clone_documents(template, source, schema, fields)

      fields.each do |field|
        field['submitter_uuid'] = submitter_map[field['submitter_uuid']] || template.submitters.first['uuid']

        Array.wrap(field['areas']).each do |area|
          area['attachment_uuid'] = attachment_map.fetch(area['attachment_uuid'], area['attachment_uuid'])
        end
      end

      template.schema += schema
      template.fields += fields
    end

    # roles given → source submitter i ↦ roles[i] (positional); beyond the given roles, and when no roles are
    # given, source roles are matched by name and unknown ones appended in order of appearance.
    def map_submitters(template, submitters, roles)
      submitters.each_with_index.to_h do |submitter, index|
        target = template.submitters[index] if index < roles.size
        name = submitter['name'].presence || "Party #{index + 1}"

        [submitter['uuid'], target ? target['uuid'] : Ccn::AssignRoles.submitter_uuid_for(template, name)]
      end
    end

    # Schema items whose attachment is missing are dropped (with the fields pointing at them); the rest get
    # a fresh uuid and a new attachment on the same blob (+ cloned preview images). Returns old uuid → new uuid.
    def clone_documents(template, source, schema, fields)
      originals = source.schema_documents.preload(:blob, :preview_images_attachments).index_by(&:uuid)
      schema.reject { |item| originals.key?(item['attachment_uuid']) }
            .each { |item| Ccn::UpdateTemplateDocuments.drop_document_fields(fields, item['attachment_uuid']) }
      schema.select! { |item| originals.key?(item['attachment_uuid']) }

      schema.each_with_object({}) do |item, map|
        original = originals[item['attachment_uuid']]
        new_uuid = SecureRandom.uuid

        map[original.uuid] = new_uuid
        item['attachment_uuid'] = new_uuid
        item.delete('pending_fields')

        new_document = template.documents_attachments.new(uuid: new_uuid, blob_id: original.blob_id)
        Templates::CloneAttachments.clone_document_preview_images_attachments(document: original, new_document:)
      end
    end
  end
end
