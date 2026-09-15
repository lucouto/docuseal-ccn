# frozen_string_literal: true

module Ccn
  # Stage 4, US3 (specs/003-p1-features, research D10): UsersController#destroy archives with `update!`, so a
  # validation refusal — the last-admin guard — would reach the browser as a 500. One include turns it into
  # the same flash alert every other settings page uses. The API and MCP paths already render it as a 422
  # (Ccn::AdminErrors), so only the UI needed this.
  module UsersControllerGuard
    extend ActiveSupport::Concern

    included do
      rescue_from ActiveRecord::RecordInvalid do |e|
        redirect_back(fallback_location: settings_users_path, alert: e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
