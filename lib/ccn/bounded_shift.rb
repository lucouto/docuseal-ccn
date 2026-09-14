# frozen_string_literal: true

module Ccn
  # Prepended into Dentaku::AST::BitwiseShiftLeft / BitwiseShiftRight; mirrors dentaku 4.x Bitwise#value
  # (its two rescue clauses included) with the shift bounded first. See Ccn::FormulaBounds.
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
