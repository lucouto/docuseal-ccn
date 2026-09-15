# frozen_string_literal: true

# CCN fork — Stage 4, US1 (research D1): registers the reminder sweep with sidekiq-cron, only in the process
# that actually runs jobs, and only when explicitly enabled — off by default, on for staging
# (staging-compose.yml) and for production since 2026-09-15.
#
# Do NOT guard this with `Sidekiq.server?`. It reads `defined?(Sidekiq::CLI)`, and this image never loads the
# CLI: Sidekiq runs *embedded inside Puma* (lib/puma/plugin/sidekiq_embed.rb calls Sidekiq.configure_embed,
# and `ps` in the container shows puma and nothing else). That guard was here until 2026-09-15 and registered
# the schedule nowhere at all — the flag had been true on staging for a day and `Sidekiq::Cron::Job.all` was
# still empty, so the sweep only ever ran when somebody called the API by hand.
#
# `Sidekiq.configure_server` is the seam that works in both deployment shapes, because Sidekiq 8 *records*
# every block it is given (`@config_blocks`) and replays them inside `configure_embed` — so the block below
# runs whether Sidekiq is embedded under Puma here or started as a standalone `sidekiq` CLI elsewhere.
# Registering from the `:startup` lifecycle event rather than at Rails boot also guarantees Redis is up: the
# puma plugin waits for Redis before configuring, then fires `:startup` itself.
if ENV['CCN_REMINDERS_ENABLED'] == 'true'
  Sidekiq.configure_server do |config|
    config.on(:startup) do
      Sidekiq::Cron::Job.create(
        name: 'ccn_send_submitter_reminders',
        cron: '*/15 * * * *',
        class: 'CcnSendSubmitterRemindersJob'
      )
    end
  end
end
