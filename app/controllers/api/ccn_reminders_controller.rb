# frozen_string_literal: true

module Api
  # CCN fork — /api/ccn/reminders (specs/003-p1-features, US1). Thin over Ccn::Reminders; admins only —
  # not exposed as an MCP tool (research D6).
  class CcnRemindersController < ApiBaseController
    include Ccn::AdminErrors

    before_action { authorize!(:manage, current_account) }

    def due
      render json: { data: Ccn::Reminders.due(current_account).map { |row| serialize(row) } }
    end

    def run
      render json: Ccn::Reminders.run(account: current_account, dry_run: Ccn::DocumentParams.boolean(params[:dry_run]))
    end

    private

    def serialize(row)
      { submitter_id: row[:submitter_id], submission_id: row[:submission_id], email: row[:email],
        name: row[:name], stage: row[:stage], due_at: row[:due_at] }
    end
  end
end
