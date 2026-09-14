# frozen_string_literal: true

module Ccn
  # Stage 4, US1 (specs/003-p1-features, research D2-D4): the due rule and the sweep, shared by the Sidekiq
  # job (CcnSendSubmitterRemindersJob) and the observability API (Api::CcnRemindersController). Durations are
  # read from AccountConfig::SUBMITTER_REMINDERS (the existing settings form already saves this key); nothing
  # new is stored.
  module Reminders
    # AccountConfigs::REMINDER_DURATIONS keys, mirrored to real durations for arithmetic. A spec asserts the
    # key sets stay identical so an upstream rename breaks CI, not a silent no-op in production.
    DURATIONS = {
      'one_hour' => 1.hour,
      'two_hours' => 2.hours,
      'four_hours' => 4.hours,
      'eight_hours' => 8.hours,
      'twelve_hours' => 12.hours,
      'twenty_four_hours' => 24.hours,
      'two_days' => 2.days,
      'three_days' => 3.days,
      'four_days' => 4.days,
      'five_days' => 5.days,
      'six_days' => 6.days,
      'seven_days' => 7.days,
      'eight_days' => 8.days,
      'fifteen_days' => 15.days,
      'twenty_one_days' => 21.days,
      'thirty_days' => 30.days
    }.freeze

    STAGE_KEYS = %w[first_duration second_duration third_duration].freeze
    LATE_GRACE = 7.days
    LOCK_TTL = 14.minutes

    RELEASE_LOCK_SCRIPT = <<~LUA
      if redis.call('get', KEYS[1]) == ARGV[1] then
        return redis.call('del', KEYS[1])
      else
        return 0
      end
    LUA

    module_function

    # @return [Array<Hash>] signers due now, oldest sent_at first; each row keeps the Submitter under
    #   :submitter for #run to reuse without a second query.
    def due(account, now: Time.current)
      durations = resolve_durations(account)
      return [] if durations.blank?

      candidates(account, durations, now).filter_map { |submitter| due_row(submitter, durations, now) }
                                         .sort_by { |row| row[:due_at] }
    end

    # @return [Hash] { sent:, skipped: { reason => count }, locked:, disabled: } — dry_run computes the same
    #   counters without delivering or writing events (FR-004).
    def run(account:, now: Time.current, dry_run: false)
      return disabled_result if resolve_durations(account).blank?
      return counted(account, now) if dry_run

      lock_token = SecureRandom.uuid

      return locked_result unless acquire_lock!(account, lock_token)

      begin
        deliver_due(account, now)
      ensure
        release_lock!(account, lock_token)
      end
    end

    def max_per_run
      ENV.fetch('CCN_REMINDERS_MAX_PER_RUN', '50').to_i
    end

    def resolve_durations(account)
      config = account.account_configs.find_by(key: AccountConfig::SUBMITTER_REMINDERS)&.value

      return {} if config.blank?

      STAGE_KEYS.each_with_index.filter_map do |key, index|
        value = config[key]

        next if value.blank?

        duration = DURATIONS[value]

        [index + 1, duration] if duration
      end.to_h
    end

    def candidates(account, durations, now)
      min_due = now - durations.values.max
      max_due = now - durations.values.min

      Submitter.where(account_id: account.id)
              .where(completed_at: nil, declined_at: nil)
              .where.not(sent_at: nil)
              .where.not(email: [nil, ''])
              .joins(:submission).merge(Submission.active.non_expired)
              .where(sent_at: (min_due - LATE_GRACE)..max_due)
    end

    def due_row(submitter, durations, now)
      return if submitter.template&.archived_at.present?
      return if submitter.preferences['send_email'] == false
      return if Submitters.email_bounced_recently?(submitter.email)

      stage = submitter.submission_events.where(event_type: 'send_reminder_email').count + 1
      duration = durations[stage]

      return unless duration

      due_at = submitter.sent_at + duration

      return if now < due_at
      return if now > due_at + LATE_GRACE

      { submitter_id: submitter.id, submission_id: submitter.submission_id, email: submitter.email,
        name: submitter.name, stage:, due_at:, submitter: }
    end

    def counted(account, now)
      rows = due(account, now:).first(max_per_run)
      sendable = Accounts.can_send_emails?(account) ? rows.size : 0
      skipped = Accounts.can_send_emails?(account) ? {} : { 'no_email_delivery_configured' => rows.size }

      { sent: sendable, skipped:, locked: false, disabled: false }
    end

    def deliver_due(account, now)
      rows = due(account, now:).first(max_per_run)
      sent = 0
      skipped = Hash.new(0)

      rows.each do |row|
        if Accounts.can_send_emails?(account)
          deliver!(row[:submitter])
          sent += 1
        else
          skipped['no_email_delivery_configured'] += 1
        end
      end

      { sent:, skipped: skipped.to_h, locked: false, disabled: false }
    end

    def deliver!(submitter)
      mail = CcnSubmitterReminderMailer.reminder_email(submitter)

      Submitters::ValidateSending.call(submitter, mail)

      mail.deliver_now!

      SubmissionEvent.create!(submitter:, event_type: 'send_reminder_email')
    end

    def acquire_lock!(account, token)
      Sidekiq.redis { |redis| redis.set(lock_key(account), token, nx: true, ex: LOCK_TTL.to_i) }
    end

    def release_lock!(account, token)
      Sidekiq.redis { |redis| redis.call('EVAL', RELEASE_LOCK_SCRIPT, 1, lock_key(account), token) }
    end

    def lock_key(account)
      "ccn:reminders:lock:#{account.id}"
    end

    def disabled_result
      { sent: 0, skipped: {}, locked: false, disabled: true }
    end

    def locked_result
      { sent: 0, skipped: {}, locked: true, disabled: false }
    end
  end
end
