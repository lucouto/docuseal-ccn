# frozen_string_literal: true

# CCN fork — Stage 4, US1 (specs/003-p1-features): the sidekiq-cron *registration*, as opposed to the sweep
# (spec/lib/ccn/reminders_spec.rb) and the job (spec/jobs/ccn_send_submitter_reminders_job_spec.rb).
#
# Regression cover for a defect found on 2026-09-15, after the feature had shipped: the schedule was
# registered under `if Sidekiq.server?`, which reads `defined?(Sidekiq::CLI)` and is false in this image
# because Sidekiq runs embedded inside Puma (lib/puma/plugin/sidekiq_embed.rb). Nothing was ever scheduled —
# on staging the flag had been true for a day with `Sidekiq::Cron::Job.all` still empty. Every test here runs
# with `Sidekiq.server?` stubbed false, which is the condition the old code got wrong.
describe CcnSendSubmitterRemindersJob do
  let(:flag) { 'true' }
  let(:startup_callbacks) { [] }
  let(:sidekiq_config) do
    instance_double(Sidekiq::Config).tap do |config|
      allow(config).to receive(:on) { |event, &block| startup_callbacks << block if event == :startup }
    end
  end

  around do |example|
    original = ENV.fetch('CCN_REMINDERS_ENABLED', nil)
    ENV['CCN_REMINDERS_ENABLED'] = flag
    example.run
    ENV['CCN_REMINDERS_ENABLED'] = original
  end

  before do
    # The deployment shape this fork actually runs in: embedded Sidekiq, so no CLI and no `server?`.
    allow(Sidekiq).to receive(:server?).and_return(false)
    allow(Sidekiq).to receive(:configure_server).and_yield(sidekiq_config)
    allow(Sidekiq::Cron::Job).to receive(:create)
  end

  def load_initializer
    load Rails.root.join('config/initializers/zz_ccn_reminders.rb')
  end

  context 'when CCN_REMINDERS_ENABLED is true' do
    it 'registers through Sidekiq.configure_server, which configure_embed replays' do
      load_initializer

      expect(Sidekiq).to have_received(:configure_server)
      expect(startup_callbacks.size).to eq(1)
    end

    it 'creates the sweep on :startup even though Sidekiq.server? is false' do
      load_initializer

      startup_callbacks.each(&:call)

      expect(Sidekiq::Cron::Job).to have_received(:create).with(
        name: 'ccn_send_submitter_reminders',
        cron: '*/15 * * * *',
        class: 'CcnSendSubmitterRemindersJob'
      )
    end

    it 'does not create the job before :startup fires, so Redis is not touched at Rails boot' do
      load_initializer

      expect(Sidekiq::Cron::Job).not_to have_received(:create)
    end
  end

  context 'when CCN_REMINDERS_ENABLED is unset' do
    let(:flag) { nil }

    it 'registers nothing at all' do
      load_initializer

      expect(Sidekiq).not_to have_received(:configure_server)
      expect(Sidekiq::Cron::Job).not_to have_received(:create)
    end
  end

  context 'when CCN_REMINDERS_ENABLED is any other value' do
    let(:flag) { 'yes' }

    it 'registers nothing — the flag is exactly "true" or off' do
      load_initializer

      expect(Sidekiq).not_to have_received(:configure_server)
    end
  end
end
