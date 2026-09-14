# frozen_string_literal: true

# CCN fork — Stage 4, US1 (specs/003-p1-features): the sidekiq-cron entry point. Ccn::Reminders itself is
# covered in depth by spec/lib/ccn/reminders_spec.rb; this spec only checks the job sweeps every account that
# has reminders configured and leaves the rest alone.
describe CcnSendSubmitterRemindersJob do
  let(:configured_account) { create(:account) }
  let(:unconfigured_account) { create(:account) }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(FakeReminderRedis.new)
  end

  it 'runs the sweep only for accounts with submitter_reminders configured' do
    Ccn::ManageAccountConfigs.set(configured_account, AccountConfig::SUBMITTER_REMINDERS,
                                  { 'first_duration' => 'one_hour' })
    allow(Ccn::Reminders).to receive(:run)

    described_class.new.perform

    expect(Ccn::Reminders).to have_received(:run).once
      .with(account: configured_account, now: kind_of(ActiveSupport::TimeWithZone))
  end

  it 'does nothing when no account has reminders configured' do
    unconfigured_account
    allow(Ccn::Reminders).to receive(:run)

    described_class.new.perform

    expect(Ccn::Reminders).not_to have_received(:run)
  end
end
