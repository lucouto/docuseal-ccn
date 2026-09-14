# frozen_string_literal: true

module Ccn
  # The MCP counterpart of Ccn::IngestionErrors / Ccn::AdminErrors (specs/002-everything-by-api, FR-009): the
  # same client-caused errors, answered as MCP tool errors (`isError: true`) carrying the REST message.
  module McpToolErrors
    extend ActiveSupport::Concern

    included do
      rescue_from(*Ccn::IngestionErrors::CLIENT_ERRORS, Ccn::AdminInvalid) do |e|
        render_tool_error(Ccn::IngestionErrors.message_for(e))
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render_tool_error(e.record.errors.full_messages.to_sentence)
      end
    end
  end
end
