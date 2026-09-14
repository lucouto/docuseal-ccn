# frozen_string_literal: true

module Ccn
  # Maps the transient 'role' of detected / explicit fields onto template.submitters (created in order of
  # first appearance; the first submitter stays the default for fields without a role).
  module AssignRoles
    module_function

    # Mutates template.submitters and the fields (drops 'role', sets 'submitter_uuid'); returns the fields.
    def call(template, fields)
      fields.each do |field|
        role = field.delete('role')

        field['submitter_uuid'] = submitter_uuid_for(template, role) if field['submitter_uuid'].blank? || role.present?
      end
    end

    def submitter_uuid_for(template, role)
      role = role.to_s.squish

      return template.submitters.first['uuid'] if role.blank?

      submitter = template.submitters.find { |s| s['name'].to_s.casecmp?(role) }

      if submitter.nil?
        submitter = { 'name' => role, 'uuid' => SecureRandom.uuid }
        template.submitters << submitter
      end

      submitter['uuid']
    end
  end
end
