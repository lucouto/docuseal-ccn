# frozen_string_literal: true

# CCN fork: bound the operands of dentaku's `^`, `<<` and `>>` (see lib/ccn/formula_bounds.rb for the why
# and the limits). The modules live in lib/ccn (reloadable), so the prepend runs in to_prepare — once at
# boot in production, again after each reload in development.
Rails.configuration.to_prepare do
  Dentaku::AST::Exponentiation.prepend(Ccn::BoundedExponentiation)
  Dentaku::AST::BitwiseShiftLeft.prepend(Ccn::BoundedShift)
  Dentaku::AST::BitwiseShiftRight.prepend(Ccn::BoundedShift)
end
