# frozen_string_literal: true

module Ccn
  # PUT /api/templates/{id}/documents (FR-011, plan design 7). Each documents[] entry is, in order: `remove`
  # (by 0-based `position` or by `name`), `replace` at `position` (fields of the old document move to the new
  # one unless the new one brings its own), or add at `position` (default: last). Documents come as `file`
  # (PDF / DOCX / image, base64 or https URL) or `html`. `merge: true` then folds every document into one
  # PDF, fields re-pointed with cumulative page offsets. Attachments of removed documents stay on the
  # template (as the builder leaves them); the schema is what the API exposes.
  module UpdateTemplateDocuments
    module_function

    def call(template:, params:)
      documents = Array.wrap(params[:documents]).map { |document| Ccn::DocumentParams.indifferent(document) }

      Template.transaction do
        documents.each { |document| apply(template, document, params) }
        merge(template) if Ccn::DocumentParams.boolean(params[:merge])

        template.save!
      end

      WebhookUrls.enqueue_events(template, 'template.updated')

      template.reload
    end

    def apply(template, document, params)
      if Ccn::DocumentParams.boolean(document[:remove])
        remove(template, document)
      elsif Ccn::DocumentParams.boolean(document[:replace]) && (index = position_of(template, document))
        replace(template, index, attach(template, document, params))
      else
        add(template, document[:position], attach(template, document, params))
      end
    end

    def attach(template, document, params)
      file =
        if document[:html].present?
          Ccn::HtmlDocuments.render(document[:html], name: document[:name].presence || 'document',
                                                     size: Ccn::HtmlDocuments.page_size(params[:size]))
        else
          Ccn::DocumentParams.files_from([document]).first
        end

      attachment_params = { files: [file], remove_tags: params[:remove_tags] }
      attachments, = Templates::CreateAttachments.call(template, attachment_params, extract_fields: true)

      attachments.first
    end

    def add(template, position, attachment)
      index = Integer(position.to_s, 10, exception: false)
      index = index.nil? ? template.schema.size : index.clamp(0, template.schema.size)

      template.schema.insert(index, schema_item(attachment))
      template.fields += Templates::ProcessDocument.normalize_attachment_fields(template, [attachment])
    end

    def replace(template, index, attachment)
      old_uuid = template.schema[index]['attachment_uuid']
      detected = Templates::ProcessDocument.normalize_attachment_fields(template, [attachment])

      template.schema[index] = schema_item(attachment)

      if detected.present?
        drop_document_fields(template.fields, old_uuid)
        template.fields += detected
      else
        repoint_areas(template.fields, old_uuid, attachment.uuid)
      end
    end

    def remove(template, document)
      index = position_of(template, document)

      raise Ccn::DocumentParams::Invalid, 'remove: no document at that position / with that name' if index.nil?

      item = template.schema.delete_at(index)
      drop_document_fields(template.fields, item['attachment_uuid'])
    end

    def merge(template)
      return if template.schema.size < 2

      offsets = {}
      file = merged_file(template, offsets)
      attachments, = Templates::CreateAttachments.call(template, { files: [file] }, extract_fields: false)
      merged = attachments.first

      template.fields.each do |field|
        Array.wrap(field['areas']).each do |area|
          next unless offsets.key?(area['attachment_uuid'])

          area['page'] = area['page'].to_i + offsets[area['attachment_uuid']]
          area['attachment_uuid'] = merged.uuid
        end
      end

      template.schema = [{ 'attachment_uuid' => merged.uuid, 'name' => template.name }]
    end

    # All schema documents, in order, into one PDF (an image becomes a page, as in the builder); fills
    # `offsets` with each document's first page index in the merged file.
    def merged_file(template, offsets)
      documents = template.schema_documents.preload(:blob).index_by(&:uuid)
      default_size = Templates::ModifyDocuments.default_page_size(template.account)
      io = StringIO.new

      Pdfium.with_instance do
        Pdfium::Document.create do |merged|
          template.schema.each do |item|
            attachment = documents[item['attachment_uuid']]

            next if attachment.nil?

            offsets[attachment.uuid] = merged.page_count
            source = Templates::ModifyDocuments.open_or_build_pdf(attachment, default_size:)
            merged.import_pages(source)
            source.close
          end

          merged.save(io)
        end
      end

      filename = ActiveStorage::Filename.new("#{template.name}.pdf").sanitized

      Ccn::DocumentParams.build_uploaded_file(io.string, filename)
    end

    def schema_item(attachment)
      { 'attachment_uuid' => attachment.uuid, 'name' => attachment.filename.base }
    end

    def position_of(template, document)
      position = Integer(document[:position].to_s, 10, exception: false)

      return position if position&.between?(0, template.schema.size - 1)
      return if document[:name].blank?

      template.schema.index { |item| item['name'].to_s.casecmp?(document[:name].to_s) }
    end

    # Removes the areas on that document; a field left with no area is removed altogether.
    def drop_document_fields(fields, attachment_uuid)
      fields.reject! do |field|
        next false if field['areas'].blank?

        field['areas'].reject! { |area| area['attachment_uuid'] == attachment_uuid }
        field['areas'].empty?
      end
    end

    def repoint_areas(fields, from_uuid, to_uuid)
      fields.each do |field|
        Array.wrap(field['areas']).each do |area|
          area['attachment_uuid'] = to_uuid if area['attachment_uuid'] == from_uuid
        end
      end
    end
  end
end
