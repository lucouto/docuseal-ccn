# frozen_string_literal: true

module Ccn
  # Stage 4, US3 (specs/003-p1-features, research D10): an account always keeps at least one administrator who
  # can actually sign in. A model validation rather than a controller check, because a user can be demoted or
  # archived from two controllers, the /api/ccn/users API, the manage_users MCP tool and a console, and only
  # the record itself sees all of them.
  #
  # `integration` users do not count, by construction: their role is not ADMIN_ROLE. They are the automation
  # accounts, they never sign in interactively, and letting one stand as "the administrator" is exactly how an
  # account locks every human out of its own settings.
  module LastAdminGuard
    extend ActiveSupport::Concern

    included do
      validate :ccn_last_admin_remains
    end

    private

    def ccn_last_admin_remains
      return unless ccn_was_active_admin?
      return unless ccn_leaves_active_admins?
      return if ccn_another_active_admin?

      errors.add(:base, I18n.t('ccn_last_admin_required'))
    end

    # Only a user who counted as an active administrator until now can be the one whose change empties the set,
    # so an invitation, or any change to somebody else, costs no query at all.
    def ccn_was_active_admin?
      persisted? && role_was == User::ADMIN_ROLE && archived_at_was.nil?
    end

    # The three ways out of "active administrator of this account": a role change, an archive, and upstream's
    # multitenant move of a user to another account.
    def ccn_leaves_active_admins?
      role != User::ADMIN_ROLE || archived_at.present? || account_id != account_id_was
    end

    def ccn_another_active_admin?
      User.where(account_id: account_id_was, role: User::ADMIN_ROLE, archived_at: nil)
          .where.not(id:)
          .exists?
    end
  end
end
