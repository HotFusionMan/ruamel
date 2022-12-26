# encoding: utf-8

# frozen_string_literal: true

# from ruamel.yaml.anchor import Anchor
require_relative './anchor'

module SweetStreetYaml
  class ScalarInt
    attr_accessor :integer, :_width, :_underscore

    def self.__new__(*args, **kw)
      width = kw.delete(:width)
      underscore = kw.delete(:underscore)
      _anchor = kw.delete(:anchor)

      # v = int.__new__(cls, *args, **kw)
      v = new
      v.integer = args.first.to_i(args[1].to_i)
      v._width = width
      v._underscore = underscore
      v.yaml_set_anchor(_anchor, :always_dump => true) if _anchor
      v
    end

    define_method(:+) { |a|
      x = self.class.__new__(@integer + a)
      x._width = _width
      x._underscore = _underscore ? _underscore[0..-1] : nil
      x
    }

    define_method('//') { |a|
      x = self.class.new((@integer / a).to_i)
      x._width = _width
      x._underscore = _underscore ? _underscore[0..-1] : nil
      x
    }

    define_method(:*) { |a|
      x = self.class.new(@integer * a)
      x._width = _width
      x._underscore = _underscore ? _underscore[0..-1] : nil
      x
    }

    define_method(:**) {
      x = self.class.new(@integer ** a)
      x._width = _width
      x._underscore = _underscore ? _underscore[0..-1] : nil
      x
    }

    define_method(:-) {
      x = self.class.new(@integer - a)
      x._width = _width
      x._underscore = _underscore ? _underscore[0..-1] : nil
      x
    }

    def anchor
      anchor_attribute_value = self.__send__(Anchor.attrib)
      return anchor_attribute_value if anchor_attribute_value

      self.__send__("#{Anchor.attrib}=", Anchor.new)
    end

    def yaml_anchor(any = false)
      return nil unless self.__send__(Anchor.attrib)

      return anchor if any || anchor.always_dump

      return nil
    end

    def yaml_set_anchor(value, always_dump: false)
      anchor.value = value
      anchor.always_dump = always_dump
    end
  end


  class BinaryInt < ScalarInt
    def self.__new__(value, width = nil, underscore = nil, anchor = nil)
      super(value, :width => width, :underscore => underscore, :anchor => anchor)
    end
  end


  class OctalInt < ScalarInt
    def self.__new__(value, width = nil, underscore = nil, anchor = nil)
      super(value, :width => width, :underscore => underscore, :anchor => anchor)
    end
  end


  # mixed casing of A-F is not supported, when loading the first non digit
  # determines the case

  class HexInt < ScalarInt
    "uses lower case (a-f)"
    def self.__new__(value, width = nil, underscore = nil, anchor = nil)
      super(value, :width => width, :underscore => underscore, :anchor => anchor)
    end
  end

  class HexCapsInt < ScalarInt
    "uses upper case (A-F)"
    def self.__new__(value, width = nil, underscore = nil, anchor = nil)
      super(value, :width => width, :underscore => underscore, :anchor => anchor)
    end
  end

  class DecimalInt < ScalarInt
    "needed if anchor"
    def self.__new__(value, width = nil, underscore = nil, anchor = nil)
      super(value, :width => width, :underscore => underscore, :anchor => anchor)
    end
  end
end
