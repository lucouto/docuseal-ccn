# frozen_string_literal: true

module Ccn
  # /api/ccn/template_folders (specs/002-everything-by-api, US4, FR-005): the UI's folder rules —
  # TemplateFolders.find_or_create_by_name for creation (two levels, "Parent / Child"), the default folder is
  # immutable, only an empty folder can be archived (the Pro-only delete that moves templates is not mirrored).
  module ManageFolders
    SERIALIZE_ONLY = %i[id name parent_folder_id archived_at created_at updated_at].freeze
    MAX_DEPTH = 2

    module_function

    # @return [ActiveRecord::Relation] unordered; the controller paginates
    def list(account)
      account.template_folders.active.preload(:parent_folder)
    end

    def create(user, name)
      name = name.to_s.squish

      raise AdminInvalid, I18n.t('ccn_folder_name_required') if name.blank?
      raise AdminInvalid, I18n.t('ccn_folder_depth') if name.split(' / ').size > MAX_DEPTH

      serialize(TemplateFolders.find_or_create_by_name(user, name))
    end

    def rename(folder, name)
      name = name.to_s.squish

      raise AdminInvalid, I18n.t('ccn_default_folder_immutable') if folder.default?
      raise AdminInvalid, I18n.t('ccn_folder_name_required') if name.blank?
      raise AdminInvalid, I18n.t('ccn_folder_depth') if name.include?(' / ')

      folder.update!(name:)

      serialize(folder)
    end

    def archive(folder)
      raise AdminInvalid, I18n.t('ccn_default_folder_immutable') if folder.default?

      if folder.active_templates.exists? || folder.subfolders.active.exists?
        raise AdminInvalid, I18n.t('ccn_folder_not_empty')
      end

      folder.update!(archived_at: Time.current)

      serialize(folder)
    end

    def serialize(folder, templates_count: nil)
      folder.as_json(only: SERIALIZE_ONLY)
            .merge('full_name' => folder.full_name,
                   'templates_count' => templates_count || folder.active_templates.count)
    end

    # A page of folders with one COUNT query instead of one per row.
    def serialize_all(folders)
      counts = Template.active.where(folder_id: folders.map(&:id)).group(:folder_id).count

      folders.map { |folder| serialize(folder, templates_count: counts.fetch(folder.id, 0)) }
    end
  end
end
