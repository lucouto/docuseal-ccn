# frozen_string_literal: true

module Ccn
  # Raised by Ccn::FormulaBounds when a formula has no real result (negative base, fractional exponent).
  class FormulaNotANumber < StandardError; end
end
