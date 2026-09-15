# frozen_string_literal: true

# CCN fork — Stage 4, US1 (specs/003-p1-features): the due rule and the sweep. CI has no Redis service
# (only Postgres — see .github/workflows/ci.yml), so Sidekiq.redis is stubbed with FakeReminderRedis
# (spec/support/fake_reminder_redis.rb) rather than a real connection; the lock code under test is exactly
# what runs on staging/production, where Sidekiq already requires a real Redis.
describe Ccn::Reminders do
  let(:account) { create(:account) }
  let(:template) { create(:template, account:) }
  let(:fake_redis) { FakeReminderRedis.new }

  before do
    create(:user, account:) # Account#default_template_folder needs an author to assign templates to
    allow(Sidekiq).to receive(:redis).and_yield(fake_redis)
    # Accounts.can_send_emails? is false by default in the test env (no EncryptedConfig SMTP row, no
    # SMTP_ADDRESS, not multitenant/development) — the same as staging; opt in per test like the rest of
    # the suite does (e.g. spec/system/profile_settings_spec.rb).
    allow(Accounts).to receive(:can_send_emails?).and_return(true)
    ActionMailer::Base.deliveries.clear
  end

  def configure_durations(first: 'twenty_four_hours', second: 'three_days', third: 'seven_days')
    Ccn::ManageAccountConfigs.set(account, AccountConfig::SUBMITTER_REMINDERS,
                                  { 'first_duration' => first, 'second_duration' => second,
                                    'third_duration' => third }.compact)
  end

  # A real signer's uuid is always one of the submission's template_submitters, which is what gives them
  # fields to fill — DocuSeal builds them that way (see the :with_submitters trait). A random uuid here would
  # be a party with nothing to sign, which .due now skips on purpose.
  def submitter_sent(**attrs)
    submission = create(:submission, template:)
    create(:submitter, submission:, account:, uuid: submission.template_submitters.first['uuid'],
                       email: Faker::Internet.email, **attrs)
  end

  # Upstream's "viewer": a party on the document with no field of their own. `is_viewer` is written by
  # Submissions::CreateFromSubmitters#assign_submitters_is_viewer; pass `flagged: false` for a submission
  # created before that ran, where only the absence of fields gives it away.
  def viewer_sent(flagged: true, **attrs)
    submission = create(:submission, template:)
    uuid = SecureRandom.uuid
    entry = { 'name' => 'In copy', 'uuid' => uuid }
    entry['is_viewer'] = true if flagged
    submission.update!(template_submitters: submission.template_submitters + [entry])

    create(:submitter, submission:, account:, uuid:, email: Faker::Internet.email, **attrs)
  end

  it 'mirrors AccountConfigs::REMINDER_DURATIONS exactly' do
    expect(described_class::DURATIONS.keys).to match_array(AccountConfigs::REMINDER_DURATIONS.keys)
  end

  describe '.due' do
    it 'returns nothing when the account has no reminders configured' do
      submitter = submitter_sent(sent_at: 2.days.ago)

      expect(described_class.due(account)).to eq([])
      expect(submitter).to be_present
    end

    it 'follows the SC-001 sequence: one reminder per stage, never early, never a fourth' do
      configure_durations

      now = Time.zone.parse('2026-09-14 12:00:00')
      submitter = travel_to(now - 25.hours) { submitter_sent(sent_at: now - 25.hours) }

      travel_to(now) do
        rows = described_class.due(account)

        expect(rows.size).to eq(1)
        expect(rows.first).to include(submitter_id: submitter.id, stage: 1)

        result = described_class.run(account:, now:)

        expect(result).to eq(sent: 1, skipped: {}, locked: false, disabled: false)
        expect(submitter.submission_events.where(event_type: 'send_reminder_email').count).to eq(1)
      end

      # immediate rerun: not due again before the second duration elapses
      travel_to(now + 1.minute) do
        expect(described_class.due(account)).to eq([])
        expect(described_class.run(account:, now: now + 1.minute)).to eq(
          sent: 0, skipped: {}, locked: false, disabled: false
        )
      end

      travel_to(now + 3.days) do
        rows = described_class.due(account)

        expect(rows.pluck(:stage)).to eq([2])

        described_class.run(account:, now: now + 3.days)

        expect(submitter.submission_events.where(event_type: 'send_reminder_email').count).to eq(2)
      end

      travel_to(now + 7.days) do
        rows = described_class.due(account)

        expect(rows.pluck(:stage)).to eq([3])

        described_class.run(account:, now: now + 7.days)

        expect(submitter.submission_events.where(event_type: 'send_reminder_email').count).to eq(3)
      end

      # a fourth stage does not exist: never due again, however long it waits
      travel_to(now + 40.days) do
        expect(described_class.due(account)).to eq([])
      end

      expect(ActionMailer::Base.deliveries.size).to eq(3)
    end

    it 'skips a signer who fell due more than 7 days ago (backlog, outage)' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      submitter_sent(sent_at: now - 1.hour - 8.days)

      expect(described_class.due(account, now:)).to eq([])
    end

    it 'skips a signer who completed, declined, or whose submission/template is archived or expired' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      due_at = now - 2.hours

      completed = submitter_sent(sent_at: due_at, completed_at: now)
      declined = submitter_sent(sent_at: due_at, declined_at: now)

      archived_submission = submitter_sent(sent_at: due_at)
      archived_submission.submission.update!(archived_at: now)

      expired_submission = submitter_sent(sent_at: due_at)
      expired_submission.submission.update!(expire_at: 1.day.ago)

      archived_template = submitter_sent(sent_at: due_at)
      archived_template.template.update!(archived_at: now)

      rows = described_class.due(account, now:)

      expect(rows).to be_empty
      [completed, declined, archived_submission, expired_submission, archived_template].each(&:reload)
    end

    it 'never chases a viewer — a party with no field has nothing to complete, flagged or not' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      due_at = now - 2.hours

      flagged = viewer_sent(sent_at: due_at)
      unflagged = viewer_sent(flagged: false, sent_at: due_at)
      signer = submitter_sent(sent_at: due_at)

      rows = described_class.due(account, now:)

      # A viewer never reaches completed_at, so without this they would be chased at every stage for ever.
      expect(rows.pluck(:submitter_id)).to eq([signer.id])
      expect(flagged.reload.completed_at).to be_nil
      expect(unflagged.reload.completed_at).to be_nil
    end

    it 'skips a signer with a blank e-mail, an opted-out preference, or a recent bounce' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      due_at = now - 2.hours

      submitter_sent(sent_at: due_at, email: nil)
      submitter_sent(sent_at: due_at, preferences: { 'send_email' => false })
      bounced = submitter_sent(sent_at: due_at)
      create(:email_event, emailable: bounced, account:, email: bounced.email, event_type: 'bounce',
                           event_datetime: 1.hour.ago)

      expect(described_class.due(account, now:)).to be_empty
    end

    it 'orders by sent_at, not due_at, when stages and durations differ' do
      configure_durations(first: 'twenty_four_hours', second: 'one_hour', third: nil)
      now = Time.current

      older = submitter_sent(sent_at: now - 25.hours) # stage 1, 24h → fell due an hour ago
      newer = submitter_sent(sent_at: now - 3.hours)  # stage 2, 1h  → fell due two hours ago
      create(:submission_event, submitter: newer, submission: newer.submission,
                                event_type: 'send_reminder_email')

      expect(described_class.due(account, now:).pluck(:submitter_id)).to eq([older.id, newer.id])
    end

    it 'never sent (sent_at nil) is never due' do
      configure_durations(first: 'one_hour', second: nil, third: nil)

      create(:submitter, submission: create(:submission, template:), account:, uuid: SecureRandom.uuid, sent_at: nil)

      expect(described_class.due(account)).to eq([])
    end
  end

  describe '.run' do
    it 'reports "no_email_delivery_configured" and writes no event when the account cannot send e-mail' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      allow(Accounts).to receive(:can_send_emails?).and_return(false)
      now = Time.current
      submitter = submitter_sent(sent_at: now - 2.hours)

      result = described_class.run(account:, now:)

      expect(result).to eq(sent: 0, skipped: { 'no_email_delivery_configured' => 1 }, locked: false, disabled: false)
      expect(submitter.submission_events.where(event_type: 'send_reminder_email')).to be_none
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'reports disabled: true and sends nothing when reminders are not configured' do
      expect(described_class.run(account:)).to eq(sent: 0, skipped: {}, locked: false, disabled: true)
    end

    it 'dry_run counts without delivering or writing an event' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      submitter = submitter_sent(sent_at: now - 2.hours)

      result = described_class.run(account:, now:, dry_run: true)

      expect(result).to eq(sent: 1, skipped: {}, locked: false, disabled: false)
      expect(submitter.submission_events.where(event_type: 'send_reminder_email')).to be_none
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'a concurrent run finds the lock held and sends nothing' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      submitter_sent(sent_at: now - 2.hours)

      fake_redis.set(described_class.lock_key(account), 'someone-else', nx: true, ex: 840)

      expect(described_class.run(account:, now:)).to eq(sent: 0, skipped: {}, locked: true, disabled: false)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'releases the lock after a run so the next run can proceed' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      submitter_sent(sent_at: now - 2.hours)

      described_class.run(account:, now:)

      expect(fake_redis.instance_variable_get(:@store)).not_to have_key(described_class.lock_key(account))
    end

    it 'skips an unroutable address and keeps sweeping the signers queued behind it' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      # ordered oldest sent_at first, so the bad row is reached before the good one
      invalid = submitter_sent(sent_at: now - 3.hours, email: 'signer-without-an-at-sign')
      valid = submitter_sent(sent_at: now - 2.hours)

      result = described_class.run(account:, now:)

      expect(result).to eq(sent: 1, skipped: { 'invalid_email' => 1 }, locked: false, disabled: false)
      expect(invalid.submission_events.where(event_type: 'send_reminder_email')).to be_none
      expect(valid.submission_events.where(event_type: 'send_reminder_email')).to be_one
    end

    it 'caps deliveries at CCN_REMINDERS_MAX_PER_RUN, oldest sent_at first' do
      configure_durations(first: 'one_hour', second: nil, third: nil)
      now = Time.current
      older = submitter_sent(sent_at: now - 3.hours)
      newer = submitter_sent(sent_at: now - 2.hours)

      original = ENV.fetch('CCN_REMINDERS_MAX_PER_RUN', nil)
      ENV['CCN_REMINDERS_MAX_PER_RUN'] = '1'

      begin
        result = described_class.run(account:, now:)

        expect(result[:sent]).to eq(1)
        expect(older.submission_events.where(event_type: 'send_reminder_email')).to be_one
        expect(newer.submission_events.where(event_type: 'send_reminder_email')).to be_none
      ensure
        ENV['CCN_REMINDERS_MAX_PER_RUN'] = original
      end
    end
  end
end
