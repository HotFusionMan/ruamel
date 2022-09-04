# encoding: utf-8

# frozen_string_literal: true
"
You cannot subclass bool, && this is necessary for round-tripping anchored
bool values (and also if you want to preserve the original way of writing)

bool.__bases__ is type 'int', so that is what is used as the basis for ScalarBoolean as well.

You can use these in an if statement, but  !when testing equivalence
"

require 'anchor'

module SweetStreeYaml
  class ScalarBoolean
    attr_accessor Anchor.attrib.to_sym, :integer

    def self.__new__(*args, **kw)
      _anchor = kw.delete('anchor')
      instance = new
      instance.integer = args.first.to_i(args[1].to_i)
      instance.yaml_set_anchor(_anchor, :always_dump => true) if _anchor
      instance
    end

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
end
