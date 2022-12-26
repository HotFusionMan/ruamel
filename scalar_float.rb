# coding: utf-8

# frozen_string_literal: true

# from ruamel.yaml.anchor import Anchor
require_relative './anchor'

module SweetStreetYaml
  class Float
    attr_accessor :_width, :_prec, :_m_sign, :_m_lead0, :_exp, :_e_width, :_e_sign, :_underscore
  end

  class ScalarFloat < Float
    attr_accessor :float

    def self.__new__(*args, **kw)
      width = kw.delete(:width)
      prec = kw.delete(:prec)
      m_sign = kw.delete(:m_sign)
      m_lead0 = kw.delete(:m_lead0) || 0
      exp = kw.delete(:exp)
      e_width = kw.delete(:e_width)
      e_sign = kw.delete(:e_sign)
      underscore = kw.delete(:underscore)
      anchor = kw.delete(:anchor)

      v = new
      v.float = args.first.to_f
      v._width = width
      v._prec = prec
      v._m_sign = m_sign
      v._m_lead0 = m_lead0
      v._exp = exp
      v._e_width = e_width
      v._e_sign = e_sign
      v._underscore = underscore
      v.yaml_set_anchor(anchor, always_dump=true) if anchor
      v
    end

    define_method(:+) { |a|
      return @float + a
      # x = type(self + a)
      # x._width = _width
      # x._underscore = _underscore[:] if _underscore !.nil? else nil
      # return x
    }

    define_method('//') { |a|
      return (@float / a).to_i
      # x = type(self // a)
      # x._width = _width
      # x._underscore = _underscore[:] if _underscore !.nil? else nil  # NOQA
      # return x
    }

    define_method(:*) { |a|
      return @float * a
      # x = type(self * a)
      # x._width = _width
      # x._underscore = _underscore[:] if _underscore !.nil? else nil  # NOQA
      # x._prec = _prec  # check for others
      # return x
    }

    define_method(:**) { |a|
      return @float ** a
      # x = type(self ** a)
      # x._width = _width
      # x._underscore = _underscore[:] if _underscore !.nil? else nil  # NOQA
      # return x
    }

    define_method(:-) { |a|
      return @float - a
      # x = type(self - a)
      # x._width = _width
      # x._underscore = _underscore[:] if _underscore !.nil? else nil  # NOQA
      # return x
    }

    def anchor
      anchor_attribute_value = self.__send__(Anchor.attrib)
      return anchor_attribute_value if anchor_attribute_value

      self.__send__("#{Anchor.attrib}=", Anchor.new)
    end

    def yaml_anchor(any = false)
      return nil unless self.__send__(Anchor.attrib)

      return anchor if any || anchor.always_dump

      nil
    end

    def yaml_set_anchor(value, always_dump: false)
      anchor.value = value
      anchor.always_dump = always_dump
    end

    def dump(out = STDOUT)
      out.puts("ScalarFloat(#{to_s}| w:#{@_width}, p:#{@_prec}, s:#{@_m_sign}, lz:#{@_m_lead0}, _:#{@_underscore}|#{@_exp}, w:#{@_e_width}, s:#{@_e_sign})")
    end
  end


  class ExponentialFloat < ScalarFloat
    def self.__new__(value, width = nil, underscore = nil)
      super(value, :width => width, :underscore => underscore)
    end
  end

  class ExponentialCapsFloat < ScalarFloat
    def self.__new__(value, width = nil, underscore = nil)
      super(value, :width => width, :underscore => underscore)
    end
  end
end
