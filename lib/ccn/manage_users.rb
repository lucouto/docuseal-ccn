# frozen_string_literal: true

module Ccn
  # /api/ccn/users and the manage_users MCP tool (specs/002-everything-by-api, US1, FR-001): the UI's
  # UsersController rules — account-scoped list filters, reactivation of an archived e-mail, default role and
  # password, self guards, reconfirmation job, invitation mail — as plain functions over hashes, so that REST
  # and MCP behave identically.
  module ManageUsers
    ATTRIBUTES = %w[email first_name last_name password archived_at otp_required_for_login role].freeze
    SELF_GUARDED = %w[role otp_required_for_login archived_at archived].freeze
    STATUSES = %w[active archived integration].freeze
    SERIALIZE_ONLY = %i[id email first_name last_name role archived_at otp_required_for_login
                        current_sign_in_at last_sign_in_at created_at updated_at].freeze
    RESET_LIMIT = 10.minutes

    module_function

    # @return [ActiveRecord::Relation] unordered; the controller paginates
    def list(account, status: nil)
      users = account.users

      case status.to_s
      when '', 'active' then users.active.where.not(role: 'integration')
      when 'archived' then users.archived.where.not(role: 'integration')
      when 'integration' then users.active.where(role: 'integration')
      else raise AdminInvalid, I18n.t('ccn_unknown_status', status:, statuses: STATUSES.join(', '))
      end
    end

    # An archived user with the same e-mail in this account is reactivated (as the UI does); an active one is
    # refused; an e-mail taken in another account fails Devise's uniqueness validation (422, no account named).
    def invite(account, actor, attrs, send_email: true)
      attrs = permitted(attrs).except('archived_at', 'archived')
      user = account.users.new(attrs)
      existing = account.users.find_by(email: user.email.to_s.strip.downcase) if user.email.present?

      if existing
        raise AdminInvalid, I18n.t('ccn_user_exists') unless existing.archived_at?

        existing.assign_attributes(attrs.slice('first_name', 'last_name', 'role').compact_blank)
        existing.archived_at = nil
        user = existing
      end

      user.password = SecureRandom.hex if user.password.blank?
      user.role = User::ADMIN_ROLE unless User::ROLES.include?(user.role)
      user.save!

      UserMailer.invitation_email(user, invited_by: actor).deliver_later! if send_email

      serialize(user)
    end

    def update(user, actor, attrs)
      attrs = permitted(attrs)

      raise AdminInvalid, I18n.t('ccn_self_change_refused') if user == actor && attrs.keys.intersect?(SELF_GUARDED)
      # As the UI (UsersController#update strips `password` for everyone): a password is set at invitation only;
      # afterwards the user resets it through the e-mailed instructions.
      raise AdminInvalid, I18n.t('ccn_password_immutable') if attrs['password'].present?

      changes = attrs.except('archived', 'archived_at', 'password').reject { |_, value| value.blank? && value != false }
      changes.merge!(archived_attrs(attrs))

      user.update!(changes)

      # The UI's branch; Devise :confirmable is not enabled in this edition (app/models/user.rb), so a changed
      # e-mail takes effect immediately and no reconfirmation is queued.
      if user.try(:pending_reconfirmation?) && user.previous_changes.key?('unconfirmed_email')
        SendConfirmationInstructionsJob.perform_async('user_id' => user.id)
      end

      serialize(user)
    end

    def archive(user, actor)
      raise AdminInvalid, I18n.t('ccn_self_change_refused') if user == actor

      user.update!(archived_at: Time.current)

      serialize(user)
    end

    # Devise's reset instructions, throttled like the UI (UsersSendResetPasswordController::LIMIT_DURATION).
    def send_reset_password(user)
      raise AdminInvalid, I18n.t('ccn_user_archived') if user.archived_at?

      if user.reset_password_sent_at && user.reset_password_sent_at > RESET_LIMIT.ago
        raise AdminInvalid, I18n.t('ccn_reset_already_sent')
      end

      user.send_reset_password_instructions

      { 'sent' => true }
    end

    def serialize(user)
      user.as_json(only: SERIALIZE_ONLY)
    end

    # The UI's permitted list; `role` only when it names an existing role; `otp_required_for_login` as a
    # boolean; `archived` (boolean) as a convenience next to `archived_at`.
    def permitted(attrs)
      attrs = Ccn::DocumentParams.indifferent(attrs).slice(*ATTRIBUTES, 'archived').to_h

      if attrs.key?('role') && User::ROLES.exclude?(attrs['role'])
        raise AdminInvalid, I18n.t('ccn_invalid_role', role: attrs['role'], roles: User::ROLES.join(', '))
      end

      if attrs.key?('otp_required_for_login')
        attrs['otp_required_for_login'] = Ccn::DocumentParams.boolean(attrs['otp_required_for_login'])
      end

      attrs
    end

    # `archived: true/false` or `archived_at: <time>/null` → the column value (blank means unarchive).
    def archived_attrs(attrs)
      if attrs.key?('archived')
        { 'archived_at' => Ccn::DocumentParams.boolean(attrs['archived']) ? Time.current : nil }
      elsif attrs.key?('archived_at')
        { 'archived_at' => parse_time(attrs['archived_at']) }
      else
        {}
      end
    end

    # A date-time string or blank (unarchive); anything unreadable is refused instead of being cast to nil.
    def parse_time(value)
      return if value.blank?

      time = value.is_a?(String) ? Time.zone.parse(value) : nil

      raise AdminInvalid, I18n.t('ccn_invalid_archived_at') if time.nil?

      time
    rescue ArgumentError
      raise AdminInvalid, I18n.t('ccn_invalid_archived_at')
    end
  end
end
