# frozen_string_literal: true

# CCN fork: bounds for the three dentaku operations whose cost grows with the magnitude of an operand.
# BigDecimal#** is exact (7 ^ 100000 has 84510 digits, 7 ^ 100000000 never finishes) and Integer#<<
# allocates one bit per unit of shift (1 << 1e19 raises NoMemoryError), so a signer-controlled value in
# `{{a}} ^ {{b}}` or `ROUND({{a}}) << {{b}}` could otherwise burn CPU or memory for minutes. The checks live
# in the operators themselves, so they run exactly where dentaku evaluates them: an untaken IF branch is
# never checked and a nested `^` is bounded from the inside out. Submitters::SubmitValues turns the errors
# into HTTP 422 messages. Pinned to dentaku 4.x internals (Arithmetic#calculate, Bitwise#value).
module Ccn
  class FormulaOutOfRange < StandardError; end
  class FormulaNotANumber < StandardError; end

  module FormulaBounds
    MAX_BASE_DIGITS = 100 # digits needed to write the left operand of ^ in plain decimal
    MAX_EXPONENT = 1000 # absolute value of the right operand of ^
    # base digits × |exponent| = size of the exact result. The base of a rate-divided compounding formula
    # such as 1 + {{rate}} / 100 / 12 has 35-36 digits, so 40 000 admits every positive exponent up to
    # MAX_EXPONENT (≈ 50-100 ms worst case). A negative exponent costs ~5× more per digit (reciprocal
    # division), so its budget is smaller but still admits (1 + r / 12) ^ -360 annuity formulas (≈ 12 600
    # digits, ≈ 70 ms worst case).
    MAX_RESULT_DIGITS = 40_000
    MAX_RESULT_DIGITS_NEGATIVE = 15_000
    MAX_SHIFT = 64 # absolute value of the right operand of << and >>

    module_function

    def check_exponentiation!(base, exponent)
      base_decimal = bounded!(base) { |decimal| decimal.precision <= MAX_BASE_DIGITS }
      exponent_decimal = bounded!(exponent) { |decimal| decimal.abs <= MAX_EXPONENT }

      return unless base_decimal && exponent_decimal
      raise FormulaNotANumber if base_decimal.negative? && exponent_decimal.frac.nonzero?

      budget = exponent_decimal.negative? ? MAX_RESULT_DIGITS_NEGATIVE : MAX_RESULT_DIGITS

      raise FormulaOutOfRange if base_decimal.precision * exponent_decimal.abs > budget
    end

    def check_shift!(shift)
      bounded!(shift) { |decimal| decimal.abs <= MAX_SHIFT }
    end

    # Operands are coerced the way dentaku's Arithmetic#cast coerces them for ^ (a numeric string such as
    # "1e9" reached through an IF branch becomes a number), so the bound applies to what ^ will actually
    # compute with. Dentaku's Bitwise does not coerce, so for << and >> a numeric string is bounded here and
    # then rejected by dentaku itself. Whatever is still not a number is left to dentaku's own type errors.
    # Numbers must be finite reals that satisfy the block (NaN, Infinity and Complex are refused).
    def bounded!(operand)
      operand = Dentaku::NumericParser.ensure_numeric(operand) || operand

      return nil unless operand.is_a?(Numeric)

      operand_decimal = decimal(operand)

      raise FormulaOutOfRange if operand_decimal.nil? || !yield(operand_decimal)

      operand_decimal
    end

    # BigDecimal#precision counts every digit needed to write the number out in plain decimal (1e20 → 21,
    # 1e-20 → 20), so it bounds magnitude in both directions, not just the mantissa.
    def decimal(number)
      case number
      when BigDecimal then number.finite? ? number : nil
      when Integer then BigDecimal(number)
      when Numeric then number.real? && number.finite? ? BigDecimal(number.to_s) : nil
      end
    rescue ArgumentError, TypeError
      nil
    end
  end

  module BoundedExponentiation
    def value(context = {})
      base = left.value(context)
      exponent = right.value(context)

      FormulaBounds.check_exponentiation!(base, exponent)

      calculate(base, exponent)
    end
  end

  module BoundedShift
    def value(context = {})
      left_value = left.value(context)
      right_value = right.value(context)

      FormulaBounds.check_shift!(right_value)

      left_value.public_send(operator, right_value)
    rescue NoMethodError => e
      raise Dentaku::ArgumentError.for(:incompatible_type, actual: left_value, expected: Integer), e.message
    rescue TypeError => e
      raise Dentaku::ArgumentError.for(:incompatible_type, actual: right_value, expected: Integer), e.message
    end
  end
end

Dentaku::AST::Exponentiation.prepend(Ccn::BoundedExponentiation)
Dentaku::AST::BitwiseShiftLeft.prepend(Ccn::BoundedShift)
Dentaku::AST::BitwiseShiftRight.prepend(Ccn::BoundedShift)
