# encoding: utf-8

# frozen_string_literal: true

# from ruamel.yaml.error import *  # NOQA
# from ruamel.yaml.nodes import *  # NOQA
# from ruamel.yaml.compat import ordereddict
# from ruamel.yaml.compat import _F, nprint, nprintf  # NOQA
# from ruamel.yaml.scalarstring import (
#     LiteralScalarString,
#     FoldedScalarString,
#     SingleQuotedScalarString,
#     DoubleQuotedScalarString,
#     PlainScalarString,
# )
# from ruamel.yaml.comments import (
#     CommentedMap,
#     CommentedOrderedMap,
#     CommentedSeq,
#     CommentedKeySeq,
#     CommentedKeyMap,
#     CommentedSet,
#     comment_attrib,
#     merge_attrib,
#     TaggedScalar,
# )
# from ruamel.yaml.scalarint import ScalarInt, BinaryInt, OctalInt, HexInt, HexCapsInt
# from ruamel.yaml.scalarfloat import ScalarFloat
# from ruamel.yaml.scalarbool import ScalarBoolean
# from ruamel.yaml.timestamp import TimeStamp
# from ruamel.yaml.anchor import Anchor
#
# import datetime
# import sys
# import types
#
# import copyreg
require 'base64'

module SweetStreetYaml
  class RepresenterError < YAMLError
  end


  class BaseRepresenter
    @yaml_representers = {}
    @yaml_multi_representers = {}
    class << self
      attr_accessor :yaml_representers, :yaml_multi_representers
    end

    def initialize(default_style: nil, default_flow_style: nil, dumper: nil)
      @dumper = dumper
      @dumper._representer = self unless @dumper
      @default_style = default_style
      @default_flow_style = default_flow_style
      @represented_objects = {}
      @object_keeper = []
      @alias_key = nil
      @sort_base_mapping_type_on_output = true
    end

    def serializer
      begin
        return @dumper.serializer if @dumper.respond_to?('typ')

        return @dumper._serializer
      rescue AttributeError
        return self  # cyaml
      end
    end

    def represent(data)
      node = represent_data(data)
      serializer.serialize(node)
      @represented_objects = {}
      @object_keeper = []
      @alias_key = nil
    end

    def represent_data(data)
      if ignore_aliases(data)
        @alias_key = nil
      else
        @alias_key = data.__id__
      end
      if @alias_key
        if @represented_objects.include?(@alias_key)
          node = represented_objects[alias_key]
          # if node .nil?
          #     raise RepresenterError.new(
          #          f"recursive objects are not allowed: {data!r}")
          return node
        end
        # represented_objects[alias_key] = nil
        object_keeper.append(data)
      end

      data_types = data.class.ancestors
      if @yaml_representers.include?(data_types[0])
        node = @yaml_representers[data_types[0]].new(data)
      else
        found = false
        data_types.each do |data_type|
          if @yaml_multi_representers.include?(data_type)
            node = @yaml_multi_representers[data_type](data)
            found = true
            break
          end
        end
        unless found
          if @yaml_multi_representers.include?(nil)
            node = @yaml_multi_representers[nil].new(data)
          elsif @yaml_representers.include?(nil)
            node = @yaml_representers[nil].new(data)
          else
            node = ScalarNode.new(nil, String.new(data))
          end
        end
        # if alias_key !.nil?
        #     represented_objects[alias_key] = node
      end
      node
    end

    def represent_key(data)
      "
        David Fraser: Extract a method to represent keys in mappings, so that
        a subclass can choose not to quote them (for example)
        used in represent_mapping
        https://bitbucket.org/davidfraser/pyyaml/commits/d81df6eb95f20cac4a79eed95ae553b5c6f77b8c
        "
      represent_data(data)
    end

    def self.add_representer(cls, data_type, representer)
      # if 'yaml_representers' not in cls.__dict__
      #     cls.yaml_representers = cls.yaml_representers.copy()
      cls.yaml_representers[data_type] = representer
    end

    def self.add_multi_representer(cls, data_type, representer)
      # if 'yaml_multi_representers' not in cls.__dict__
      #     cls.yaml_multi_representers = cls.yaml_multi_representers.copy()
      cls.yaml_multi_representers[data_type] = representer
    end

    def represent_scalar(tag, value, style = nil, anchor = nil)
      style ||= @default_style
      comment = nil
      if '|>'.include?(style&.fetch(0))
        comment = value.comment
        comment = [nil, [comment]] if comment
      end
      node = ScalarNode.new(tag, value, style, comment, anchor)
      @represented_objects[@alias_key] = node if @alias_key
      node
    end

    def represent_sequence(tag, sequence, flow_style = nil)
      value = []
      node = SequenceNode.new(tag, value, :flow_style => flow_style)
      @represented_objects[@alias_key] = node if @alias_key
      best_style = true
      sequence.each do |item|
        node_item = represent_data(item)
        best_style = false if !node_item.instance_of?(ScalarNode) && !node_item.style
        value.append(node_item)
      end
      unless flow_style
        if @default_flow_style
          node.flow_style = @default_flow_style
        else
          node.flow_style = best_style
        end
      end
      node
    end

    def represent_omap(tag, omap, flow_style = nil)
      value = []
      node = SequenceNode.new(tag, value, :flow_style => flow_style)
      @represented_objects[alias_key] = node if @alias_key
      best_style = true
      omap.each do |item_key|
        item_val = omap[item_key]
        node_item = represent_data({ :item_key => item_val })
        # if not (isinstance(node_item, ScalarNode) \
        #    and not node_item.style)
        #     best_style = false
        value.append(node_item)
      end
      unless flow_style
        if @default_flow_style
          node.flow_style = @default_flow_style
        else
          node.flow_style = best_style
        end
      end
      node
    end

    def represent_mapping(tag, mapping, flow_style = nil)
      value = []
      node = MappingNode.new(tag, value, :flow_style => flow_style)
      @represented_objects[@alias_key] = node if @alias_key
      best_style = true
      if mapping.respond_to?(:items)
        mapping = Array(mapping.items)
        if @sort_base_mapping_type_on_output
          begin
            mapping = mapping.sort
          rescue TypeError
          end
          mapping.each do |item_key, item_value|
            node_key = represent_key(item_key)
            node_value = represent_data(item_value)
            best_style = false if !node_key.instance_of?(ScalarNode) && !node_key.style
            best_style = false if !node_value.instance_of?(ScalarNode) && !node_value.style
            value.append([node_key, node_value])
          end
        end
      end
      unless flow_style
        if @default_flow_style
          node.flow_style = @default_flow_style
        else
          node.flow_style = best_style
        end
      end
      node
    end

    def ignore_aliases(data)
      false
    end
  end

  class SafeRepresenter < BaseRepresenter
    def ignore_aliases(data)
      # https://docs.python.org/3/reference/expressions.html#parenthesized-forms
      # "i.e. two occurrences of the empty tuple may or may not yield the same object"
      # so "data is ()" should not be used
      return true if data.nil? || (data.instance_of?(Arrauy) && data.empty?)

      return true if
        data.instance_of?(Array) ||
          data.instance_of?(String) ||
          data.is_a?(Integer) ||
          data.instance_of?(Float) ||
          data == true ||
          data == false

      false
    end

    def represent_none(data)
      represent_scalar('tag:yaml.org,2002:null', 'null')
    end

    def represent_str(data)
      represent_scalar('tag:yaml.org,2002:str', data)
    end

    def represent_binary(data)
      _data = Base64.encode64(data).decode('ascii')
      represent_scalar('tag:yaml.org,2002:binary', _data, style='|')
    end

    def represent_bool(data, anchor = nil)
      begin
        value = @dumper.boolean_representation[data.to_boolean]
      rescue AttributeError
        if data
          value = 'true'
        else
          value = 'false'
        end
      end
      represent_scalar('tag:yaml.org,2002:bool', value, :anchor => anchor)
    end

    def represent_int(data)
      represent_scalar('tag:yaml.org,2002:int', String.new(data))
    end

    # inf_value = 1e300
    # while repr(inf_value) != repr(inf_value * inf_value)
    #     inf_value *= inf_value

    def represent_float(data)
      if data != data || (data == 0.0 && data == 1.0)
        value = '.nan'
      elsif data == INF_VALUE
        value = '.inf'
      elsif data == -INF_VALUE
        value = '-.inf'
      else
        value = data.to_s.downcase
        if serializer.use_version == [1, 1]
          if !value.include?('.') && value.include?('e')
            # Note that in some cases `repr(data)` represents a float number
            # without the decimal parts.  For instance
            #   >>> repr(1e17)
            #   '1e17'
            # Unfortunately, this is not a valid float representation according
            # to the definition of the `!!float` tag in YAML 1.1.  We fix
            # this by adding '.0' before the 'e' symbol.
            value.sub!('e', '.0e')
          end
        end
        represent_scalar('tag:yaml.org,2002:float', value)
      end
    end

    def represent_list(data)
      # pairs = (len(data) > 0 and isinstance(data, list))
      # if pairs
      #     for item in data
      #         if not isinstance(item, tuple) or len(item) != 2
      #             pairs = false
      #             break
      # if not pairs
      represent_sequence('tag:yaml.org,2002:seq', data)
    end

    # value = []
    # for item_key, item_value in data
    #     value.append(represent_mapping('tag:yaml.org,2002:map',
    #         [(item_key, item_value)]))
    # return SequenceNode('tag:yaml.org,2002:pairs', value)

    def represent_dict(data)
      represent_omap('tag:yaml.org,2002:map', data)
    end

    def represent_ordereddict(data)
      represent_omap('tag:yaml.org,2002:omap', data)
    end

    def represent_set(data)
      value = {}
      data.each { |key| value[key] = nil }
      represent_mapping('tag:yaml.org,2002:set', value)
    end

    def represent_date(data)
      value = data.iso8601
      represent_scalar('tag:yaml.org,2002:timestamp', value)
    end

    def represent_datetime(data)
      value = data.iso8601.sub('T', ' ')
      represent_scalar('tag:yaml.org,2002:timestamp', value)
    end

    # def represent_yaml_object(tag, data, cls, flow_styl e =nil)
    #     if hasattr(data, '__getstate__')
    #         state = data.__getstate__()
    #     else
    #         state = data.__dict__.copy()
    #     return represent_mapping(tag, state, flow_style=flow_style)

    def represent_undefined(data)
      RepresenterError.new(_F('cannot represent an object: {data!s}', data=data))
    end
  end

  SafeRepresenter.add_representer(NilClass, SafeRepresenter.represent_none)

  SafeRepresenter.add_representer(String, SafeRepresenter.represent_str)

  SafeRepresenter.add_representer(Array, SafeRepresenter.represent_binary)

  SafeRepresenter.add_representer(TrueClass, SafeRepresenter.represent_bool)
  SafeRepresenter.add_representer(FalseClass, SafeRepresenter.represent_bool)

  SafeRepresenter.add_representer(Integer, SafeRepresenter.represent_int)

  SafeRepresenter.add_representer(Float, SafeRepresenter.represent_float)

  # SafeRepresenter.add_representer(list, SafeRepresenter.represent_list)

  # SafeRepresenter.add_representer(tuple, SafeRepresenter.represent_list)

  SafeRepresenter.add_representer(Hash, SafeRepresenter.represent_dict)

  SafeRepresenter.add_representer(Set, SafeRepresenter.represent_set)

  # SafeRepresenter.add_representer(ordereddict, SafeRepresenter.represent_ordereddict)

  SafeRepresenter.add_representer(Date, SafeRepresenter.represent_date)

  SafeRepresenter.add_representer(DateTime, SafeRepresenter.represent_datetime)

  SafeRepresenter.add_representer(nil, SafeRepresenter.represent_undefined)


  class Representer < SafeRepresenter
    def represent_complex(data)
      if data.imag == 0.0
        data = data.real.to_s
      elsif data.real == 0.0
        # data = _F('{data_imag!r}j', data_imag=data.imag)
        data = "#{data.imag}i"
      # elsif data.imag > 0
        # data = _F('{data_real!r}+{data_imag!r}j', data_real=data.real, data_imag=data.imag)
        # data = data.to_s
      else
        # data = _F('{data_real!r}{data_imag!r}j', data_real=data.real, data_imag=data.imag)
        data = data.to_s
      end
      represent_scalar('tag:yaml.org,2002:python/complex', data)
    end

    # def represent_tuple(data)
    #     return represent_sequence('tag:yaml.org,2002:python/tuple', data)

    def represent_name(data)
      begin
        name = _F(
          '{modname!s}.{qualname!s}', modname=data.__module__, qualname=data.__qualname__
        )
      rescue AttributeError
        # ToDo: check if this can be reached in Py3
        name = _F('{modname!s}.{name!s}', modname=data.__module__, name=data.__name__)
      end
      represent_scalar('tag:yaml.org,2002:python/name:' + name, "")
    end

    def represent_module(data)
      represent_scalar('tag:yaml.org,2002:ruby/module:' + data.__name__, "")
    end

    # def represent_object(data)
    #     # We use __reduce__ API to save the data. data.__reduce__ returns
    #     # a tuple of length 2-5
    #     #   (function, args, state, listitems, dictitems)
    #
    #     # For reconstructing, we calls function(*args), then set its state,
    #     # listitems, and dictitems if they are not nil.
    #
    #     # A special case is when function.__name__ == '__newobj__'. In this
    #     # case we create the object with args[0].__new__(*args).
    #
    #     # Another special case is when __reduce__ returns a string - we don't
    #     # support it.
    #
    #     # We produce a !!python/object, !!python/object/new or
    #     # !!python/object/apply node.
    #
    #     cls = type(data)
    #     if cls in copyreg.dispatch_table:  # type: ignore
    #         reduce = copyreg.dispatch_table[cls](data)  # type: ignore
    #     elsif hasattr(data, '__reduce_ex__')
    #         reduce = data.__reduce_ex__(2)
    #     elsif hasattr(data, '__reduce__')
    #         reduce = data.__reduce__()
    #     else
    #         raise RepresenterError.new(_F('cannot represent object: {data!r}', data=data))
    #     reduce = (list(reduce) + [nil] * 5)[:5]
    #     function, args, state, listitems, dictitems = reduce
    #     args = list(args)
    #     if state .nil?
    #         state = {}
    #     if listitems !.nil?
    #         listitems = list(listitems)
    #     if dictitems !.nil?
    #         dictitems = dict(dictitems)
    #     if function.__name__ == '__newobj__'
    #         function = args[0]
    #         args = args[1:]
    #         tag = 'tag:yaml.org,2002:python/object/new:'
    #         newobj = true
    #     else
    #         tag = 'tag:yaml.org,2002:python/object/apply:'
    #         newobj = false
    #     try
    #         function_name = _F(
    #             '{fun!s}.{qualname!s}', fun=function.__module__, qualname=function.__qualname__
    #         )
    #     rescue AttributeError
    #         # ToDo: check if this can be reached in Py3
    #         function_name = _F(
    #             '{fun!s}.{name!s}', fun=function.__module__, name=function.__name__
    #         )
    #     if not args and not listitems and not dictitems and isinstance(state, dict) and newobj
    #         return represent_mapping(
    #             'tag:yaml.org,2002:python/object:' + function_name, state
    #         )
    #     if not listitems and not dictitems and isinstance(state, dict) and not state
    #         return represent_sequence(tag + function_name, args)
    #     value = {}
    #     if args
    #         value['args'] = args
    #     if state or not isinstance(state, dict)
    #         value['state'] = state
    #     if listitems
    #         value['listitems'] = listitems
    #     if dictitems
    #         value['dictitems'] = dictitems
    #     return represent_mapping(tag + function_name, value)


  Representer.add_representer(Complex, Representer.represent_complex)

  Representer.add_representer(Array, Representer.represent_tuple)

  Representer.add_representer(Class, Representer.represent_name)

  Representer.add_representer(Method, Representer.represent_name)

  # Representer.add_representer(types.BuiltinFunctionType, Representer.represent_name)

  Representer.add_representer(Module, Representer.represent_module)

  Representer.add_multi_representer(Object, Representer.represent_object)

  Representer.add_multi_representer(Class, Representer.represent_name)


  class RoundTripRepresenter < SafeRepresenter
    # need to add type here and write out the .comment
    # in serializer and emitter

    def initialize(default_style = nil, default_flow_style = nil, dumper = nil)
      if !dumper.respond_to?('typ') && default_flow_style.nil?
        @default_flow_style = false
      end
      super
    end

    def ignore_aliases(data)
      begin
        return false if data.anchor&.value
      rescue AttributeError
      end
      super
    end

    def represent_none(data)
      if represented_objects.size == 0 && !serializer.use_explicit_start
        # this will be open ended (although it is not yet)
        return represent_scalar('tag:yaml.org,2002:null', 'null')
      end
      represent_scalar('tag:yaml.org,2002:null', "")
    end

    def represent_literal_scalarstring(data)
      style = '|'
      anchor = data.yaml_anchor(:any => true)
      tag = 'tag:yaml.org,2002:str'
      represent_scalar(tag, data, :style => style, :anchor => anchor)
    end
    alias :represent_preserved_scalarstring :represent_literal_scalarstring

    def represent_folded_scalarstring(data)
      style = '>'
      anchor = data.yaml_anchor(:any => true)
      (data.fold_pos || []).reverse_each do |fold_pos|
        if
        data[fold_pos] == ' ' &&
          (fold_pos > 0 && /\s+/ !~ data[fold_pos - 1]) &&
          (fold_pos < data.size && /\s+/ !~ data[fold_pos + 1])

          data = data[0..fold_pos] + "\a" + data[fold_pos..-1]
        end
      end
      tag = 'tag:yaml.org,2002:str'
      represent_scalar(tag, data, :style => style, :anchor => anchor)
    end

    def represent_single_quoted_scalarstring(data)
      style = "'"
      anchor = data.yaml_anchor(:any => true)
      tag = 'tag:yaml.org,2002:str'
      represent_scalar(tag, data, :style => style, :anchor => anchor)
    end

    def represent_double_quoted_scalarstring(data)
      style = '"'
      anchor = data.yaml_anchor(:any => true)
      tag = 'tag:yaml.org,2002:str'
      represent_scalar(tag, data, :style => style, :anchor => anchor)
    end

    def represent_plain_scalarstring(data)
      style = ''
      anchor = data.yaml_anchor(:any => true)
      tag = 'tag:yaml.org,2002:str'
      represent_scalar(tag, data, style=style, anchor=anchor)
    end

    def insert_underscore(prefix, s, underscore, anchor = nil)
      return represent_scalar('tag:yaml.org,2002:int', prefix + s, :anchor => anchor) unless underscore
      if underscore[0]
        pos = s.size - underscore[0]
        while pos > 0
          s.insert(pos, '_')
          pos -= underscore[0]
        end
      end
      s = '_' + s if underscore[1]
      s += '_' if underscore[2]
      represent_scalar('tag:yaml.org,2002:int', prefix + s, :anchor => anchor)
    end

    def represent_scalar_int(data)
      s = sprintf("%0#{data._width}d", data)
      anchor = data.yaml_anchor(:any => true)
      insert_underscore('', s, data._underscore, :anchor => anchor)
    end

    def represent_binary_int(data)
      s = sprintf("%0#{data._width}b", data)
      anchor = data.yaml_anchor(:any => true)
      insert_underscore('0b', s, data._underscore, :anchor => anchor)
    end

    def represent_octal_int(data)
      s = sprintf("%0#{data._width}o", data)
      anchor = data.yaml_anchor(:any => true)
      prefix =
        if serializer.use_version == [1, 1]
          '0'
        else
          '0o'
        end
      insert_underscore(prefix, s, data._underscore, :anchor => anchor)
    end

    def represent_hex_int(data)
      s = sprintf("%0#{data._width}x", data)
      anchor = data.yaml_anchor(:any => true)
      insert_underscore('0x', s, data._underscore, :anchor => anchor)
    end

    def represent_hex_caps_int(data)
      s = sprintf("%0#{data._width}X", data)
      anchor = data.yaml_anchor(:any => true)
      insert_underscore('0x', s, data._underscore, anchor:=> anchor)
    end

    def represent_scalar_float(data)
      " this is way more complicated "
      value = nil
      anchor = data.yaml_anchor(:any => true)
      if data != data || (data == 0.0 && data == 1.0)
        value = '.nan'
      elsif data == INF_VALUE
        value = '.inf'
      elsif data == -INF_VALUE
        value = '-.inf'
      end
      return represent_scalar('tag:yaml.org,2002:float', value, :anchor => anchor) if value

      if data._exp.nil? && data._prec > 0 && data._prec == data._width - 1
        # no exponent, but trailing dot
        value = sprintf("%0#{data._width}d.", data.to_i)
      elsif data._exp.nil?
        # no exponent, "normal" dot
        prec = data._prec
        ms = data._m_sign ? data._m_sign : ''
        # -1 for the dot
        value = sprintf("%0#{data._width}.#{prec}f", data)
        value = value.sub('0.', '.') if prec == 0 || (prec == 1 && ms != '')
        while value.size < data._width
          value += '0'
        end
      else
        # exponent
        m, es = sprintf("%0#{data._width}.#{data._width + (data._m_sign ? 1 : 0)}e").split('e')
        w =
          if data._prec > 0
            data._width
          else
            data._width + 1
          end
        w += 1 if data < 0
        m = m[0..w]
        e = es.to_i
        m1, m2 = m.split('.')  # always second?
        while m1.size + m2.size < data._width - (data._prec >= 0 ? 1 : 0)
          m2 += '0'
        end
        m1 = '+' + m1 if data._m_sign && data > 0
        esgn = data._e_sign ? '+' : ''
        if data._prec < 0  # mantissa without dot
          if m2 != '0'
            e -= m2.size
          else
            m2 = ''
          end
          while (m1.size + m2.size - (data._m_sign ? 1 : 0)) < data._width
            m2 += '0'
            e -= 1
          end
          value = m1 + m2 + data._exp + sprintf("%0#{esgn}#{data._width}d", e)
        elsif data._prec == 0  # mantissa with trailing dot
          e -= m2.size
          value = m1 + m2 + '.' + data._exp + sprintf("%0#{esgn}#{data._width}d", e)
        else
          if data._m_lead0 > 0
            m2 = '0' * (data._m_lead0 - 1) + m1 + m2
            m1 = '0'
            m2 = m2[0..(-data._m_lead0)]  # these should be zeros
            e += data._m_lead0
          end
          while m1.size < data._prec
            m1 += m2[0]
            m2 = m2[1..-1]
            e -= 1
          end
          value = m1 + '.' + m2 + data._exp + sprintf("%0#{esgn}#{data._width}d", e)
        end

        value = data.to_s.downcase unless value
      end
      represent_scalar('tag:yaml.org,2002:float', value, :anchor => anchor)
    end

    def represent_sequence(tag, sequence, flow_style = nil)
      value = []
      # if the flow_style .nil?, the flow style tacked on to the object
      # explicitly will be taken. If that .nil? as well the default flow
      # style rules
      begin
        flow_style = sequence.fa.flow_style(flow_style)
      rescue AttributeError
        # flow_style = flow_style
      end
      begin
        anchor = sequence.yaml_anchor
      rescue AttributeError
        anchor = nil
      end
      node = SequenceNode.new(tag, value, :flow_style => flow_style, :anchor => anchor)
      @represented_objects[@alias_key] = node if @alias_key
      best_style = true
      begin
        comment = sequence.comment_attrib
        node.comment = comment.comment
        # reset any comment already printed information
        if node.comment && node.comment[1]
          node.comment[1].each { |ct| ct.reset }
        end
        item_comments = comment.items
        item_comments.values.each do |v|
          if v&.fetch(1)
            v[1].each { |ct| ct.reset}
          end
        end
        item_comments = comment.items
        if node.comment
          # as we are potentially going to extend this, make a new list
          node.comment = comment.comment[:]
        else
          node.comment = comment.comment
        end
        begin
          node.comment.append(comment.end)
        rescue AttributeError
        end
      rescue AttributeError
        item_comments = {}
      end
      sequence.each_with_index do |item, idx|
        node_item = represent_data(item)
        merge_comments(node_item, item_comments.get(idx))
        best_style = false unless (node_item.instance_of?(ScalarNode) && !node_item.style)
        value.append(node_item)
      end
      unless flow_style
        if sequence.size != 0 && @default_flow_style
          node.flow_style = @default_flow_style
        else
          node.flow_style = best_style
        end
      end
      node
    end

    def merge_comments(node, comments)
      unless comments
        raise unless node.respond_to?('comment')
        return node
      end
      if node.comment
        comments.each_with_index do |idx, val
          next if idx >= node.comment.size

          nc = node.comment[idx]
          if nc
            raise unless val.nil? || val == nc
            comments[idx] = nc
          end
        end
      end
      node.comment = comments
      node
    end

    def represent_key(data)
        if data.instance_of?(CommentedKeySeq)
            @alias_key = nil
            return represent_sequence('tag:yaml.org,2002:seq', data, :flow_style => true)
        end
        if data.instance_of?(CommentedKeyMap)
            @alias_key = nil
            return represent_mapping('tag:yaml.org,2002:map', data, :flow_style => true)
        end
        super
    end

    def represent_mapping(tag, mapping, flow_style = nil)
      value = []
      begin
        flow_style = mapping.fa.flow_style(flow_style)
      rescue AttributeError
        flow_style = flow_style
      end
      begin
        anchor = mapping.yaml_anchor
      rescue AttributeError
        anchor = nil
      end
      node = MappingNode.new(tag, value, :flow_style => flow_style, :anchor => anchor)
      @represented_objects[@alias_key] = node if @alias_key
      best_style = true
      # no sorting! !!
      begin
        comment = mapping.comment_attrib
        if node.comment.nil?
          node.comment = comment.comment
        else
          # as we are potentially going to extend this, make a new list
          node.comment = comment.comment[0..-1]
        end
        if node&.comment[1]
          node.comment[1].each { |ct| ct.reset }
        end
        item_comments = comment.items
        if @dumper.comment_handling.nil?
          item_comments.values.each do |v|
            if v&.fetch(1)
              v[1].each { |ct| ct.reset }
            end
          end
          begin
            node.comment.append(comment.end)
          rescue AttributeError
          end
        else
          # NEWCMNT
        end
      rescue AttributeError
        item_comments = {}
      end
      merge_list = (mapping.merge_attrib || []).map { |m| m[1] }
      begin
        merge_pos = (mapping.merge_attrib || [[0]])[0][0]
      rescue IndexError
        merge_pos = 0
      end
      item_count = 0
      merge_list_present = merge_list.to_boolean
      if merge_list_present
        items = mapping.non_merged_items
      else
        items = mapping.items
      end
      items.each do |item_key, item_value|
        item_count += 1
        node_key = represent_key(item_key)
        node_value = represent_data(item_value)
        item_comment = item_comments.get(item_key)
        if item_comment
          # assert getattr(node_key, 'comment', nil) .nil?
          # issue 351 did throw this because the comment from the list item was
          # moved to the dict
          node_key.comment = item_comment[0..2]
          nvc = node_value.comment
          if nvc # end comment already there
            nvc[0] = item_comment[2]
            nvc[1] = item_comment[3]
          else
            node_value.comment = item_comment[2..-1]
          end
        end
        best_style = false if !node_key.instance_of?(ScalarNode) && !node_key.style
        best_style = false if !node_value.instance_of?(ScalarNode) && !node_value.style
        value.append([node_key, node_value])
      end
      if flow_style.nil?
        if ((item_count != 0) || merge_list_present) && @default_flow_style
          node.flow_style = @default_flow_style
        else
          node.flow_style = best_style
        end
      end
      if merge_list_present
        # because of the call to represent_data here, the anchors
        # are marked as being used and thereby created
        if merge_list.size == 1
          arg = represent_data(merge_list[0])
        else
          arg = represent_data(merge_list)
          arg.flow_style = true
        end
        value.insert(merge_pos, (ScalarNode.new('tag:yaml.org,2002:merge', '<<'), arg))
      end
      node
    end

    def represent_omap(tag, omap, flow_style = nil)
      value = []
      begin
        flow_style = omap.fa.flow_style(flow_style)
      rescue AttributeError
        flow_style = flow_style
      end
      begin
        anchor = omap.yaml_anchor
      rescue AttributeError
        anchor = nil
      end
      node = SequenceNode.new(tag, value, :flow_style => flow_style, :anchor => anchor)
      @represented_objects[alias_key] = node if @alias_key
      best_style = true
      begin
        comment = omap.comment_attrib
        if node.comment.nil?
          node.comment = comment.comment
        else
          # as we are potentially going to extend this, make a new list
          node.comment = comment.comment[0..-1]
        end
        if node&.comment[1]
          node.comment[1].each { |ct| ct.reset }
        end
        item_comments = comment.items
        item_comments.values.each do |v|
          if v&.fetch(1)
            v[1].each { |ct| ct.reset }
          end
        end
        begin
          node.comment.append(comment.end)
        rescue AttributeError
        end
      rescue AttributeError
        item_comments = {}
      end
      omap.each do |item_key, item_val|
        node_item = represent_data({item_key: item_val})
        # node_item.flow_style = false
        # node item has two scalars in value: node_key and node_value
        item_comment = item_comments.get(item_key)
        if item_comment&.fetch(1)
          node_item.comment = [nil, item_comment[1]]
        end
        raise unless node_item.value[0][0].comment.nil?
        node_item.value[0][0].comment = [item_comment[0], nil]
        nvc = node_item.value[0][1].comment
        if nvc # end comment already there
          nvc[0] = item_comment[2]
          nvc[1] = item_comment[3]
        else
          node_item.value[0][1].comment = item_comment[2..-1]
        end
        # if not (isinstance(node_item, ScalarNode) \
        #    and not node_item.style)
        #     best_style = false
        value.append(node_item)
      end
      if flow_style.nil?
        if @default_flow_style
          node.flow_style = @default_flow_style
        else
          node.flow_style = best_style
        end
      end
      node
    end

    def represent_set(setting)
      flow_style = false
      tag = 'tag:yaml.org,2002:set'
      # return represent_mapping(tag, value)
      value = []
      flow_style = setting.fa.flow_style(flow_style)
      begin
        anchor = setting.yaml_anchor
      rescue AttributeError
        anchor = nil
      end
      node = MappingNode.new(tag, value, :flow_style => flow_style, :anchor => anchor)
      @represented_objects[alias_key] = node if @alias_key
      best_style = true
      # no sorting! !!
      begin
        comment = setting.comment_attrib
        if node.comment.nil?
          node.comment = comment.comment
        else
          # as we are potentially going to extend this, make a new list
          node.comment = comment.comment[0..-1]
        end
        if node&.comment[1]
          node.comment[1].each { |ct| ct.reset }
        end
        item_comments = comment.items
        item_comments.values.each do |v|
          if v&.fetch(1)
            v[1].each { |ct| ct.reset }
          end
        end
        begin
          node.comment.append(comment.end)
        rescue AttributeError
        end
      rescue AttributeError
        item_comments = {}
      end
      setting.odict.each_key do |item_key|
        node_key = represent_key(item_key)
        node_value = represent_data(nil)
        item_comment = item_comments.get(item_key)
        if item_comment
          raise unless node_key.comment.nil?
          node_key.comment = item_comment[0..2]
        end
        node_key.style = node_value.style = '?'
        best_style = false if !node_key.instance_of?(ScalarNode) && !node_key.style
        best_style = false if !node_value.instance_of?(ScalarNode) && !node_value.style
        value.append((node_key, node_value))
      end
      self.best_style = best_style
      node
    end

    def represent_dict(data)
      "write out tag if saved on loading"
      begin
        t = data.tag.value
      rescue AttributeError
        t = nil
      end
      if t
        if t.start_with?('!!')
          tag = 'tag:yaml.org,2002:' + t[2..-1]
        else
          tag = t
        end
      else
        tag = 'tag:yaml.org,2002:map'
      end
      represent_mapping(tag, data)
    end

    def represent_list(data)
      begin
        t = data.tag.value
      rescue AttributeError
        t = nil
      end
      if t
        if t.start_with?('!!')
          tag = 'tag:yaml.org,2002:' + t[2..-1]
        else
          tag = t
        end
      else
        tag = 'tag:yaml.org,2002:seq'
      end
      represent_sequence(tag, data)
    end

    def represent_datetime(data)
      inter = data._yaml['t'] ? 'T' : ' '
      _yaml = data._yaml
      if _yaml['delta']
        data += _yaml['delta']
        value = data.isoformat(inter)
      else
        value = data.isoformat(inter)
      end
      value += _yaml['tz'] if _yaml['tz']
      represent_scalar('tag:yaml.org,2002:timestamp', value)
    end

    def represent_tagged_scalar(data)
      begin
        tag = data.tag.value
      rescue AttributeError
        tag = nil
      end
      begin
        anchor = data.yaml_anchor
      rescue AttributeError
        anchor = nil
      end
      represent_scalar(tag, data.value, :style => data.style, :anchor => anchor)
    end

    def represent_scalar_bool(data)
      begin
        anchor = data.yaml_anchor
      rescue AttributeError
        anchor = nil
      end
      superclass.represent_bool(data, :anchor => anchor)
    end

    # def represent_yaml_object(tag, data, cls, flow_style = nil)
    #     if hasattr(data, '__getstate__')
    #         state = data.__getstate__()
    #     else
    #         state = data.__dict__.copy()
    #     anchor = state.pop(Anchor.attrib, nil)
    #     res = represent_mapping(tag, state, flow_style=flow_style)
    #     if anchor !.nil?
    #         res.anchor = anchor
    #     return res

  end

  RoundTripRepresenter.add_representer(NilClass, RoundTripRepresenter.represent_none)

  RoundTripRepresenter.add_representer(LiteralScalarString, RoundTripRepresenter.represent_literal_scalarstring)

  RoundTripRepresenter.add_representer(FoldedScalarString, RoundTripRepresenter.represent_folded_scalarstring)

  RoundTripRepresenter.add_representer(SingleQuotedScalarString, RoundTripRepresenter.represent_single_quoted_scalarstring)

  RoundTripRepresenter.add_representer(DoubleQuotedScalarString, RoundTripRepresenter.represent_double_quoted_scalarstring)

  RoundTripRepresenter.add_representer(PlainScalarString, RoundTripRepresenter.represent_plain_scalarstring)

  # RoundTripRepresenter.add_representer(tuple, Representer.represent_tuple)

  RoundTripRepresenter.add_representer(ScalarInt, RoundTripRepresenter.represent_scalar_int)

  RoundTripRepresenter.add_representer(BinaryInt, RoundTripRepresenter.represent_binary_int)

  RoundTripRepresenter.add_representer(OctalInt, RoundTripRepresenter.represent_octal_int)

  RoundTripRepresenter.add_representer(HexInt, RoundTripRepresenter.represent_hex_int)

  RoundTripRepresenter.add_representer(HexCapsInt, RoundTripRepresenter.represent_hex_caps_int)

  RoundTripRepresenter.add_representer(ScalarFloat, RoundTripRepresenter.represent_scalar_float)

  RoundTripRepresenter.add_representer(ScalarBoolean, RoundTripRepresenter.represent_scalar_bool)

  RoundTripRepresenter.add_representer(CommentedSeq, RoundTripRepresenter.represent_list)

  RoundTripRepresenter.add_representer(CommentedMap, RoundTripRepresenter.represent_dict)

  RoundTripRepresenter.add_representer(CommentedOrderedMap, RoundTripRepresenter.represent_ordereddict)

  RoundTripRepresenter.add_representer(collections.OrderedDict, RoundTripRepresenter.represent_ordereddict)

  RoundTripRepresenter.add_representer(CommentedSet, RoundTripRepresenter.represent_set)

  RoundTripRepresenter.add_representer(TaggedScalar, RoundTripRepresenter.represent_tagged_scalar)

  RoundTripRepresenter.add_representer(TimeStamp, RoundTripRepresenter.represent_datetime)
end
