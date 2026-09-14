# frozen_string_literal: true

module Ccn
  # Raised by Ccn::FormulaBounds when an operand or result of a formula exceeds the configured limits.
  class FormulaOutOfRange < StandardError; end
end
