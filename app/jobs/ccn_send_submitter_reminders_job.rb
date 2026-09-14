# frozen_string_literal: true

# CCN fork — Stage 4, US1: the sidekiq-cron entry point (research D1). One sweep per account that has
# submitter_reminders configured; Ccn::Reminders.run holds its own per-account lock, so overlapping ticks
# (a slow previous run, a deploy) are safe.
class CcnSendSubmitterRemindersJob
  include Sidekiq::Job

  sidekiq_options queue: 'recurrent', retry: false

  def perform
    AccountConfig.where(key: AccountConfig::SUBMITTER_REMINDERS).find_each do |config|
      next if config.value.blank?

      Ccn::Reminders.run(account: config.account, now: Time.current)
    end
  end
end
