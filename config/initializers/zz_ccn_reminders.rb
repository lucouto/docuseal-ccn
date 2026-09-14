# frozen_string_literal: true

# CCN fork — Stage 4, US1 (research D1): registers the reminder sweep with sidekiq-cron, only on a Sidekiq
# server process (never the web/console process) and only when explicitly enabled — off by default, on for
# staging (staging-compose.yml), unset on production until Luciano decides.
if ENV['CCN_REMINDERS_ENABLED'] == 'true' && Sidekiq.server?
  Rails.application.config.after_initialize do
    Sidekiq::Cron::Job.create(
      name: 'ccn_send_submitter_reminders',
      cron: '*/15 * * * *',
      class: 'CcnSendSubmitterRemindersJob'
    )
  end
end
