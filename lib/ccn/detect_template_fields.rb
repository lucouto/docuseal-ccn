# frozen_string_literal: true

module Ccn
  # POST /api/ccn/templates/{id}/detect_fields (specs/002-everything-by-api, US4, FR-007, research D8): the
  # UI's TemplatesDetectFieldsController (SSE) as one synchronous JSON answer. Candidates are returned in the
  # template's stored field shape (0-based `areas[].page`), grouped by document and 1-based page; `apply: true`
  # adds them to the first signer, skipping a candidate that overlaps an existing field on the same page.
  module DetectTemplateFields
    MAX_PAGES = 30
    OVERLAP_IOU = 0.5

    module_function

    # @param page [Integer, nil] 1-based page to detect on (all pages when nil)
    def call(template, attachment_uuid: nil, page: nil, apply: false)
      documents = select_documents(template, attachment_uuid)
      page_index = page_index(page)

      check_pages!(documents, page_index)

      results = documents.map { |document| detect(document, page_index) }
      applied = apply ? apply!(template, results) : 0

      { 'documents' => results, 'applied' => applied }
    end

    def select_documents(template, attachment_uuid)
      documents = attachment_uuid.present? ? template.documents.where(uuid: attachment_uuid) : template.schema_documents
      documents = documents.preload(:blob).to_a

      raise AdminInvalid, I18n.t('ccn_no_documents') if documents.empty?

      documents
    end

    def page_index(page)
      return if page.blank?

      number = Integer(page.to_s, 10, exception: false)

      raise AdminInvalid, I18n.t('ccn_invalid_page') if number.nil? || number < 1

      number - 1
    end

    def check_pages!(documents, page_index)
      total = documents.sum { |document| page_index ? 1 : pages_of(document) }

      raise AdminInvalid, I18n.t('ccn_too_many_pages', max: MAX_PAGES) if total > MAX_PAGES
    end

    def pages_of(document)
      document.metadata.to_h.dig('pdf', 'number_of_pages') || 1
    end

    def detect(document, page_index)
      pages = []
      io = document_io(document)

      Templates::DetectFields.call(io, attachment: document, page_number: page_index) do |(uuid, index, fields)|
        pages << { 'attachment_uuid' => uuid, 'page' => index + 1, 'fields' => fields.map(&:deep_stringify_keys) }
      end

      { 'attachment_uuid' => document.uuid, 'pages' => pages }
    end

    # As the UI: an image document is detected on its first preview image, a PDF on its bytes.
    def document_io(document)
      if document.image?
        preview = document.preview_images.joins(:blob).find_by(blob: { filename: ['0.png', '0.jpg'] })

        StringIO.new(preview.download)
      else
        StringIO.new(document.download)
      end
    end

    def apply!(template, results)
      submitter_uuid = template.submitters.first&.dig('uuid')

      raise AdminInvalid, I18n.t('ccn_no_submitters') if submitter_uuid.blank?

      existing_areas = template.fields.flat_map { |field| Array.wrap(field['areas']) }
      candidates = results.flat_map { |document| document['pages'].flat_map { |page| page['fields'] } }
      added = candidates.reject { |candidate| overlaps?(candidate, existing_areas) }

      return 0 if added.empty?

      template.fields += added.map do |candidate|
        candidate.merge('name' => '', 'submitter_uuid' => submitter_uuid, 'required' => candidate['required'] == true)
      end
      template.save!

      WebhookUrls.enqueue_events(template, 'template.updated')

      added.size
    end

    def overlaps?(candidate, areas)
      Array.wrap(candidate['areas']).any? do |area|
        areas.any? do |other|
          area['page'] == other['page'] && area['attachment_uuid'] == other['attachment_uuid'] &&
            iou(area, other) > OVERLAP_IOU
        end
      end
    end

    def iou(area, other)
      intersection = overlap(area['x'], area['w'], other['x'], other['w']) *
                     overlap(area['y'], area['h'], other['y'], other['h'])
      union = (area['w'].to_f * area['h'].to_f) + (other['w'].to_f * other['h'].to_f) - intersection

      union.positive? ? intersection / union : 0
    end

    def overlap(start_a, size_a, start_b, size_b)
      [[start_a.to_f + size_a.to_f, start_b.to_f + size_b.to_f].min - [start_a.to_f, start_b.to_f].max, 0].max
    end
  end
end
