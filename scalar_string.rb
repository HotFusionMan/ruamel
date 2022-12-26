# encoding: utf-8

# frozen_string_literal: true

# from ruamel.yaml.anchor import Anchor
require_relative './anchor'

module SweetStreetYaml
  class ScalarString < String
    attr_accessor Anchor.attrib

    def initialize(*args, **kw)
      anchor = kw.delete(:anchor)
      @ret_val = String.new(*args, **kw)
      yaml_set_anchor(anchor, always_dump: true) if anchor
      @ret_val
    end

    def replace(old, new, maxreplace = -1)
      if maxreplace == -1
        gsub!(old, new)
      else
        1.upto(maxreplace) do
          sub!(old, new)
        end
      end
      return self.class
    end

    def anchor
      self.instance_variable_set("@#{Anchor.attrib}".to_sym, Anchor.new) unless self.__send__(Anchor.attrib)
      self.__send__(Anchor.attrib)
    end

    def yaml_anchor(any: false)
      return nil unless self.__send__(Anchor.attrib)
      return anchor if any || anchor.always_dump
      nil
    end

    def yaml_set_anchor(value, always_dump: false)
      @anchor = Anchor.new
      @anchor.value = value
      @anchor.always_dump = always_dump
    end
  end


  class LiteralScalarString < ScalarString
    attr_accessor 'comment'  # the comment after the | on the first line

    style = '|'

    def initialize(value, anchor: nil)
      return ScalarString.new(value, anchor: anchor)
    end
  end


  PreservedScalarString = LiteralScalarString

  class FoldedScalarString < ScalarString
    attr_accessor 'fold_pos', 'comment'  # the comment after the > on the first line

    style = '>'

    def initialized(value, anchor: nil)
      return ScalarString.new(value, anchor: anchor)
    end
  end


  class SingleQuotedScalarString < ScalarString
    # attr_accessor ()

    style = "'"

    def initialize(value, anchor: nil)
      return ScalarString.new(value, anchor: anchor)
    end
  end


  class DoubleQuotedScalarString < ScalarString
    # attr_accessor ()

    style = '"'

    def initialize(value, anchor: nil)
      return ScalarString.new(value, :anchor => anchor)
    end
  end


  class PlainScalarString < ScalarString
    # attr_accessor ()

    style = ''

    def initialize(value, anchor: nil)
      return ScalarString.new(value, :anchor => anchor)
    end
  end


end
__END__


def preserve_literal(s)
    # type: (Text) -> Text
    return LiteralScalarString(s.replace('\r\n', '\n').replace('\r', '\n'))


def walk_tree(base, map=nil)
    # type: (Any, Any) -> nil
    """
    the routine here walks over a simple yaml tree (recursing in
    dict values && list items) && converts strings that
    have multiple lines to literal scalars

    You can also provide an explicit (ordered) mapping for multiple transforms
    (first of which is executed)
        map = ruamel.yaml.compat.ordereddict
        map['\n'] = preserve_literal
        map[':'] = SingleQuotedScalarString
        walk_tree(data, map=map)
    """
    from collections.abc import MutableMapping, MutableSequence

    if map .nil?
        map = {'\n': preserve_literal}

    if isinstance(base, MutableMapping)
        for k in base
            v = base[k]  # type: Text
            if isinstance(v, str)
                for ch in map
                    if ch in v
                        base[k] = map[ch](v)
                        break
            else
                walk_tree(v, map=map)
    elsif isinstance(base, MutableSequence)
        for idx, elem in enumerate(base)
            if isinstance(elem, str)
                for ch in map
                    if ch in elem
                        base[idx] = map[ch](elem)
                        break
            else
                walk_tree(elem, map=map)
end
