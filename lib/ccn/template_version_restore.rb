# frozen_string_literal: true

module Ccn
  # POST /api/ccn/templates/{id}/versions/{version_id}/restore (specs/002-everything-by-api, US4, FR-006,
  # research D7). The OSS UI has no server-side restore (the builder loads a version and saves); this one
  # snapshots the current state first, then puts the version's name, schema, submitters, variables and fields
  # back — only when every document the version's schema names is still one of the template's.
  module TemplateVersionRestore
    module_function

    def call(template, version, author:)
      data = version.data.to_h

      raise Ccn::NotSupportedYet, 'restoring dynamic documents' if data['dynamic_documents'].present?

      uuids = Array.wrap(data['schema']).filter_map { |item| item['attachment_uuid'] }
      present = template.documents_attachments.where(uuid: uuids).pluck(:uuid)

      raise AdminInvalid, I18n.t('ccn_version_documents_missing') if (uuids - present).any?

      TemplateVersions.find_or_create_for(template, author:) # the state before the restore stays reachable

      template.assign_attributes(data.slice(*TemplateVersions::DATA_FIELDS.map(&:to_s)))
      template.save!

      WebhookUrls.enqueue_events(template, 'template.updated')
      SearchEntries.enqueue_reindex(template)

      template
    end
  end
end
