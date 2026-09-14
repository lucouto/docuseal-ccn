# frozen_string_literal: true

module Ccn
  # Prepended into Dentaku::AST::Exponentiation (dentaku 4.x internals: Arithmetic#calculate is private and
  # the operands are evaluated by Arithmetic#value). See Ccn::FormulaBounds.
  module BoundedExponentiation
    def value(context = {})
      base = left.value(context)
      exponent = right.value(context)

      FormulaBounds.check_exponentiation!(base, exponent)

      calculate(base, exponent)
    end
  end
end
