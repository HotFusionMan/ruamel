# frozen_string_literal: true

require 'lib/'
require 'numeric_extensions'

module SweetStreetYaml
  using NumericExtensions

  inf_value = 1e300
  while inf_value != inf_value * inf_value
    inf_value *= inf_value
  end
  INF_VALUE = inf_value
  NAN_VALUE = -INF_VALUE / INF_VALUE  # Trying to make a quiet NaN (like C99).
end
