# frozen_string_literal: true

require 'lib/'
require 'rubygems/version'
require 'numeric_extensions'

VERSION_1_1 = Gem::Version.new('1.1').freeze
VERSION_1_2 = Gem::Version.new('1.2').freeze
DEFAULT_YAML_VERSION = VERSION_1_2

module SweetStreetYaml
  using NumericExtensions

  inf_value = 1e300
  while inf_value != inf_value * inf_value
    inf_value *= inf_value
  end
  INF_VALUE = inf_value
  NAN_VALUE = -INF_VALUE / INF_VALUE  # Trying to make a quiet NaN (like C99).
end
