# frozen_string_literal: true

# CCN fork: bound the operands of dentaku's `^`, `<<` and `>>` (see lib/ccn/formula_bounds.rb for the why
# and the limits). The modules live in lib/ccn (reloadable) while dentaku's classes are not, so the prepend
# runs in to_prepare and only once per process: a development reload keeps the first copy of the modules
# (restart the server after editing them) instead of stacking a new copy on the ancestor chain each time.
Rails.configuration.to_prepare do
  prepended = ->(klass, name) { klass.ancestors.any? { |mod| mod.name == name } }

  unless prepended.call(Dentaku::AST::Exponentiation, 'Ccn::BoundedExponentiation')
    Dentaku::AST::Exponentiation.prepend(Ccn::BoundedExponentiation)
  end

  unless prepended.call(Dentaku::AST::BitwiseShiftLeft, 'Ccn::BoundedShift')
    Dentaku::AST::BitwiseShiftLeft.prepend(Ccn::BoundedShift)
    Dentaku::AST::BitwiseShiftRight.prepend(Ccn::BoundedShift)
  end
end
