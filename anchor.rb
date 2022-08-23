# encoding: utf-8

# frozen_string_literal: true

module SweetStreetYaml
  class Anchor
    attr_accessor :value, :always_dump

    def self.attrib
      '_yaml_anchor'
    end

    def initialize
      @value = nil
      @always_dump = false
    end

    def to_s
      ad = always_dump ? ', (always dump)' : ''
      "Anchor(#{value}#{ad})"
    end
  end
end
