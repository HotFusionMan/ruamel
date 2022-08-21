# coding: utf-8

# frozen_string_literal: true

# import datetime
# import base64
# import binascii
# import types
# import warnings
# from collections.abc import Hashable, MutableSequence, MutableMapping

require 'base64'
require 'complex'
require 'set'

require 'error'
require 'nodes'
require 'compat'
require 'comments'
require 'scalarstring'
require 'scalarint'
require 'scalarfloat'
require 'scalarbool'
require 'serializer'
require 'timestamp'
require 'util'


module SweetStreetYaml
  class ConstructorError < MarkedYAMLError
  end


  class DuplicateKeyError < MarkedYAMLError
  end


  class BaseConstructor
    def initialize(preserve_quotes: nil, loader: nil)
      @loader = loader
      @loader._constructor = self unless @loader&._constructor
      @yaml_base_dict_type = Hash
      @yaml_base_list_type = Array
      @constructed_objects = {}
      @recursive_objects = {}
      @state_generators = []
      @deep_construct = false
      @preserve_quotes = preserve_quotes
    end

    @yaml_constructors = {}
    @yaml_multi_constructors = {}
    def self.yaml_constructors
      @yaml_constructors 
    end
    def yaml_constructors
      self.class.yaml_constructors
    end
    def self.yaml_multiconstructors
      @yaml_multiconstructors 
    end
    def yaml_multiconstructors
      self.class.yaml_multiconstructors
    end

    def composer
      return @loader.composer if @loader.respond_to?('typ')

      begin
        return @loader._composer
      rescue AttributeError
        sys.stdout.write('slt {}\n'.format(type))
        sys.stdout.write('slc {}\n'.format(@loader._composer))
        sys.stdout.write('{}\n'.format(dir))
        raise
      end
    end

    def resolver
      return @loader.resolver if @loader.respond_to?('typ')

      return @loader._resolver
    end

    def scanner
      # needed to get to the expanded comments
      return @loader.scanner if @loader.respond_to?('typ')

      return @loader._scanner
    end

    def check_data
      # If there are more documents available?
      composer.check_node
    end

    def get_data
      # Construct and return the next document.
      construct_document(composer.get_node) if composer.check_node
    end

    def get_single_data
      # Ensure that the stream contains a single document and construct it.
      node = composer.get_single_node
      construct_document(node) unless node.nil?
    end


    def construct_document(node)
      data = construct_object(node)
      until @state_generators.empty?
        old_state_generators = @state_generators
        @state_generators = []
        old_state_generators.each do |generator|
          generator.each { |_dummy| }
        end
      end
      @constructed_objects = {}
      @recursive_objects = {}
      @deep_construct = false
      data
    end

    def construct_object(node, deep = false)
      "deep is true when creating an object/mapping recursively, in that case want the underlying elements available during construction"
      return @constructed_objects[node] if @constructed_objects.include?(node)

      return @recursive_objects[node] if @recursive_objects.include?(node)

      if deep
        old_deep = @deep_construct
        @deep_construct = true
      end

      @recursive_objects[node] = nil
      data = construct_non_recursive_object(node)

      @constructed_objects[node] = data
      @recursive_objects.delete(node)
      @deep_construct = old_deep if deep
      data
    end

    def construct_non_recursive_object(node, tag = nil)
      constructor = nil
      tag_suffix = nil
      tag ||= node.tag
      if yaml_constructors.include?(tag)
        constructor = yaml_constructors[tag]
      else
        found = false
        yaml_multi_constructors.each do |tag_prefix|
          if tag.start_with?(tag_prefix)
            tag_suffix = tag[tag_prefix.size..-1]
            constructor = yaml_multi_constructors[tag_prefix]
            found = true
            break
          end
        end
        unless found
          if yaml_multi_constructors.include?('NULL TAG')
            tag_suffix = tag
            constructor = yaml_multi_constructors['NULL TAG']
          elsif yaml_constructors.include?('NULL TAG')
            constructor = yaml_constructors['NULL TAG']
          elsif node.instance_of?(ScalarNode)
            constructor = self.class.construct_scalar
          elsif node.instance_of?(SequenceNode)
            constructor = self.class.construct_sequence
          elsif node.instance_of?(MappingNode)
            constructor = self.class.construct_mapping
          end
        end
      end
      if tag_suffix
        if constructor[:is_iterator]
          generator = constructor[:constructor].call(tag_suffix, node)
          data = generator.call(tag_suffix, node)
          if @deep_construct
            generator.each { |_dummy| }
          else
            @state_generators.append(generator)
          end
        else
          data = constructor[:constructor].call(tag_suffix, node)
        end
      else
        if constructor[:is_iterator]
          generator = constructor[:constructor].call(node)
          data = generator.call(node)
          if @deep_construct
            generator.each { |_dummy| }
          else
            @state_generators.append(generator)
          end
        else
          data = constructor[:constructor].call(node)
        end
      end
      data
    end

    def construct_scalar(node)
      unless node.instance_of?(ScalarNode)
        raise ConstructorError.new(
          nil,
          nil,
          "expected a scalar node, but found #{node.id}"),
          node.start_mark
        )
      end
      node.value
    end

    def construct_sequence(node, deep = false)
      "deep is true when creating an object/mapping recursively, in that case want the underlying elements available during construction"
      unless node.instance_of?(SequenceNode)
        raise ConstructorError.new(
          nil,
          nil,
          _F('expected a sequence node, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end
      node.value.map { |child| construct_object(child, deep = deep) }
    end

    def construct_mapping(node, deep = false)
      "deep is true when creating an object/mapping recursively, in that case want the underlying elements available during construction"
      unless node.instance_of?(MappingNode)
        raise ConstructorError.new(
          nil,
          nil,
          _F('expected a mapping node, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end
      total_mapping = @yaml_base_dict_type.call
      if node.__send__('merge').nil?
        todo = [(node.value, true)]
      else
        todo = [(node.merge, false), (node.value, false)]
      end
      todo.each do |values, check|
        mapping = @yaml_base_dict_type.call
        values.each do |key_node, value_node|
          # keys can be list -> deep
          key = construct_object(key_node, true)
          # lists are not hashable, but tuples are
          # if not isinstance(key, Hashable)
          #     if isinstance(key, list)
          #         key = tuple(key)
          # if not isinstance(key, Hashable)
          #     raise ConstructorError.new(
          #         'while constructing a mapping',
          #         node.start_mark,
          #         'found unhashable key',
          #         key_node.start_mark,
          #     )

          value = construct_object(value_node, deep)
          if check
            if check_mapping_key(node, key_node, mapping, key, value)
              mapping[key] = value
            end
          else
            mapping[key] = value
          end
          total_mapping.update(mapping)
        end
        total_mapping
      end
    end

    def check_mapping_key(node, key_node, mapping, key, value)
      "return true if key is unique"
      if mapping.include?(key)
        mk = mapping.get(key)
        args = [
          'while constructing a mapping',
          node.start_mark,
          'found duplicate key "{}" with value "{}" '
        '(original value: "{}")'.format(key, value, mk),
          key_node.start_mark
        ]
        raise DuplicateKeyError.new(*args)
      end
      true
    end

    def check_set_key(node, key_node, setting, key)
      if setting.include?(key)
        args = [
          'while constructing a set',
          node.start_mark,
          'found duplicate key "{}"'.format(key),
          key_node.start_mark,
        ]
        raise DuplicateKeyError.new(*args)
      end
    end

    def construct_pairs(node, deep = false)
      unless node.instance_of?(MappingNode)
        raise ConstructorError.new(
          nil,
          nil,
          _F('expected a mapping node, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end
      pairs = []
      node.value.each do |key_node, value_node|
        key = construct_object(key_node, deep)
        value = construct_object(value_node, deep)
        pairs.append([key, value])
      end
      pairs
    end

    def self.add_constructor(tag, constructor, is_iterator = false)
      @yaml_constructors ||= superclass.instance_variable_get(:@yaml_constructors).dup unless self == BaseConstructor
      @yaml_constructors[tag] = { :constructor => constructor, :is_iterator => is_iterator }
    end

    def self.add_multi_constructor(tag_prefix, multi_constructor, is_iterator = false)
      @yaml_multi_constructors ||= superclass.instance_variable_get(:@yaml_multi_constructors).dup unless self == BaseConstructor
      @yaml_multi_constructors[tag_prefix] = { :constructor => multi_constructor, :is_iterator => is_iterator }
    end
  end


  class SafeConstructor < BaseConstructor
    def construct_scalar(node)
      if node.instance_of?(MappingNode)
        node.value.each do |key_node, value_node|
          return construct_scalar(value_node) if key_node.tag == 'tag:yaml.org,2002:value'
        end
      end
      super
    end

    def flatten_mapping(node)
      "This implements the merge key feature http://yaml.org/type/merge.html
        by inserting keys from the merge dict/list of dicts if not yet
        available in this node"
      merge = []
      index = 0
      while index < node.value.size
        key_node, value_node = node.value[index]
        case key_node.tag
          when 'tag:yaml.org,2002:merge'
            if merge
              args = [
                'while constructing a mapping',
                node.start_mark,
                'found duplicate key "{}"'.format(key_node.value),
                key_node.start_mark,
                "
                        To suppress this check see
                           http://yaml.readthedocs.io/en/latest/api.html#duplicate-keys
                        ",
                "\
                        Duplicate keys will become an error in future releases, and are errors
                        by default when using the new API.
                        ",
              ]
              raise DuplicateKeyError.new(*args)
              node.value.delete(index)
            end
            if value_node.instance_of?(MappingNode)
              flatten_mapping(value_node)
              merge.extend(value_node.value)
            elsif value_node.instance_of?(SequenceNode)
              submerge = []
              value_node.value.each do |subnode|
                unless subnode.instance_of?(MappingNode)
                  raise ConstructorError.new(
                    'while constructing a mapping',
                    node.start_mark,
                    _F(
                      'expected a mapping for merging, but found {subnode_id!s}',
                      subnode_id=subnode.id,
                      ),
                    subnode.start_mark,
                    )
                end
                flatten_mapping(subnode)
                submerge.append(subnode.value)
              end
              submerge.reverse!
              submerge.each do |value|
                merge.extend(value)
              end
            else
              raise ConstructorError.new(
                'while constructing a mapping',
                node.start_mark,
                _F(
                  'expected a mapping or list of mappings for merging, '
              'but found {value_node_id!s}',
                value_node_id=value_node.id,
              ),
                value_node.start_mark,
              )
            end
          when 'tag:yaml.org,2002:value'
            key_node.tag = 'tag:yaml.org,2002:str'
            index += 1
          else
            index += 1
        end
        if merge.to_boolean
          node.merge = merge  # separate merge keys to be able to update without duplicate
          node.value = merge + node.value
        end
      end
    end

    def construct_mapping(node, deep = false)
      "deep is true when creating an object/mapping recursively,
        in that case want the underlying elements available during construction"
      flatten_mapping(node) if node.instance_of?(MappingNode)
      BaseConstructor.construct_mapping(node, deep)
    end

    alias :construct_yaml_null :construct_scalar

    # YAML 1.2 spec doesn't mention yes/no etc any more, 1.1 does
    BOOL_VALUES = {
      'yes' => true,
      'no' => false,
      'y' => true,
      'n' => false,
      'true' => true,
      'false' => false,
      'on' => true,
      'off' => false
    }.freeze

    def construct_yaml_bool(node)
      value = construct_scalar(node)
      BOOL_VALUES[value.downcase]
    end

    def construct_yaml_int(node)
      value_s = construct_scalar(node)
      value_s.gsub!('_', '')
      sign = 1
      case value_s[0]
        when '-'
          sign = -1
        when '+-'
          value_s = value_s[1..-1]
      end
      if value_s == '0'
        return 0
      elsif value_s.start_with?('0b')
        return sign * value_s[2..-1].to_i(2)
      elsif value_s.start_with?('0x')
        return sign * value_s[2..-1].to_(16)
      elsif value_s.start_with?('0o')
        return sign * value_s[2..-1].to_i(8)
      elsif resolver.processing_version == [1, 1] && value_s[0] == '0'
        return sign * value_s.to_i(8)
      elsif resolver.processing_version == [1, 1] && value_s.incluce?(':')
        digits = value_s.split(':').map(&:to_i)
        digits.reverse!
        base = 1
        value = 0
        digits.each do |digit|
          value += digit * base
          base *= 60
        end
        return sign * value
      else
        return sign * value_s.to_i
      end
    end

    def construct_yaml_float(node)
      value_so = construct_scalar(node)
      value_s = value_so.gsub('_', '').downcase
      sign = 1
      case value_s[0]
        when'-'
          sign = -1
        when '+-'
          value_s = value_s[1..-1]
      end
      if value_s == '.inf'
        return sign * inf_value
      elsif value_s == '.nan'
        return nan_value
      elsif resolver.processing_version != [1, 2] && value_s.include?(':')
        digits = value_s.split(':').map(&:to_f)
        digits.reverse!
        base = 1
        value = 0.0
        digits.each do |digit|
          value += digit * base
          base *= 60
        end
        return sign * value
      else
        if resolver.processing_version != [1, 2] && value_s.include?('e')
          # value_s is lower case independent of input
          mantissa, exponent = value_s.split('e')
          unless mantissa.include?('.')
            warnings.warn(MantissaNoDotYAML1_1Warning(node, value_so))
          end
        end
        sign * value_s.to_f
      end
    end

    def construct_yaml_binary(node)
      begin
        value = construct_scalar(node).encode('ascii')
      rescue UnicodeEncodeError => exc
        raise ConstructorError.new(
          nil,
          nil,
          _F('failed to convert base64 data into ascii: {exc!s}', exc=exc),
          node.start_mark,
          )
      end
      begin
        return Base64.decodebytes(value)
      rescue binascii.Error => exc
        raise ConstructorError.new(
          nil,
          nil,
          _F('failed to decode base64 data: {exc!s}', exc=exc),
          node.start_mark,
          )
      end
    end


    def construct_yaml_timestamp(node, values = nil)
      if values.nil?
        begin
          match = TIMESTAMP_REGEXP.match(node.value)
        rescue TypeError
          match = nil
        end
        if match.nil?
          raise ConstructorError.new(
            nil,
            nil,
            'failed to construct timestamp from "{}"'.format(node.value),
            node.start_mark,
            )
        end
        values = match.named_captures
      end
      create_timestamp(**values)
    end

    def construct_yaml_omap(node)
      # Note: we do now check for duplicate keys
      omap = {}
      yield omap
      unless node.instance_of?(SequenceNode)
        raise ConstructorError.new(
          'while constructing an ordered map',
          node.start_mark,
          _F('expected a sequence, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end
      node.value.each do |subnode|
        unless subnode.instance_of?(MappingNode)
          raise ConstructorError.new(
            'while constructing an ordered map',
            node.start_mark,
            _F(
              'expected a mapping of length 1, but found {subnode_id!s}',
              subnode_id=subnode.id,
              ),
            subnode.start_mark,
            )
        end
        if subnode.value.size != 1
          raise ConstructorError.new(
            'while constructing an ordered map',
            node.start_mark,
            _F(
              'expected a single mapping item, but found {len_subnode_val:d} items',
              len_subnode_val=len(subnode.value),
              ),
            subnode.start_mark,
            )
        end
        key_node, value_node = subnode.value[0]
        key = construct_object(key_node)
        raise if omap.has_key?(key)
        value = construct_object(value_node)
        omap[key] = value
      end
    end

    def construct_yaml_pairs(node)
      # Note: the same code as `construct_yaml_omap`.
      pairs = []
      yield pairs
      unless node.instance_of?(SequenceNode)
        raise ConstructorError.new(
          'while constructing pairs',
          node.start_mark,
          _F('expected a sequence, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end
      node.value.each do |subnode|
        unless subnode.instance_of?(MappingNode)
          raise ConstructorError.new(
            'while constructing pairs',
            node.start_mark,
            _F(
              'expected a mapping of length 1, but found {subnode_id!s}',
              subnode_id=subnode.id,
              ),
            subnode.start_mark,
            )
        end
        if subnode.value.size != 1
          raise ConstructorError.new(
            'while constructing pairs',
            node.start_mark,
            _F(
              'expected a single mapping item, but found {len_subnode_val:d} items',
              len_subnode_val=len(subnode.value),
              ),
            subnode.start_mark,
            )
        end
        key_node, value_node = subnode.value[0]
        key = construct_object(key_node)
        value = construct_object(value_node)
        pairs.append([key, value])
      end
    end

    def construct_yaml_set(node)
      data = Set.new
      yield data
      value = construct_mapping(node)
      data.merge(value)
    end

    alias :construct_yaml_str :construct_scalar

    def construct_yaml_seq(node)
      data = @yaml_base_list_type.new
      yield data
      data.concat(construct_sequence(node))
    end

    def construct_yaml_map(node)
      data = @yaml_base_dict_type.new
      yield data
      value = construct_mapping(node)
      data.merge(value)
    end

    def construct_yaml_object(node, cls)
      data = cls.new
      yield data
      if hasattr(data, '__setstate__')
        state = construct_mapping(node, deep=true)
        data.__setstate__(state)
      else
        state = construct_mapping(node)
        data.__dict__.update(state)
      end
    end

    def construct_undefined(node)
        raise ConstructorError.new(
            nil,
            nil,
            "could not determine a constructor for the tag #{node.tag}",
            node.start_mark
        )
    end
  end

  SafeConstructor.add_constructor('tag:yaml.org,2002:null', SafeConstructor.method(:construct_yaml_null))

  SafeConstructor.add_constructor('tag:yaml.org,2002:bool', SafeConstructor.method(:construct_yaml_bool))

  SafeConstructor.add_constructor('tag:yaml.org,2002:int', SafeConstructor.method(:construct_yaml_int))

  SafeConstructor.add_constructor('tag:yaml.org,2002:float', SafeConstructor.method(:construct_yaml_float))

  SafeConstructor.add_constructor('tag:yaml.org,2002:binary', SafeConstructor.method(:construct_yaml_binary))

  SafeConstructor.add_constructor('tag:yaml.org,2002:timestamp', SafeConstructor.method(:construct_yaml_timestamp))

  SafeConstructor.add_constructor('tag:yaml.org,2002:omap', SafeConstructor.method(:construct_yaml_omap), true)

  SafeConstructor.add_constructor('tag:yaml.org,2002:pairs', SafeConstructor.method(:construct_yaml_pairs), true)

  SafeConstructor.add_constructor('tag:yaml.org,2002:set', SafeConstructor.method(:construct_yaml_set), true)

  SafeConstructor.add_constructor('tag:yaml.org,2002:str', SafeConstructor.method(:construct_yaml_str))

  SafeConstructor.add_constructor('tag:yaml.org,2002:seq', SafeConstructor.method(:construct_yaml_seq), true)

  SafeConstructor.add_constructor('tag:yaml.org,2002:map', SafeConstructor.method(:construct_yaml_map), true)

  SafeConstructor.add_constructor('NULL TAG', SafeConstructor.method(:construct_undefined))


  class Constructor < SafeConstructor
    alias :construct_python_str :construct_scalar
    alias :construct_python_unicode :construct_scalar

    def construct_python_bytes(node)
      begin
        value = construct_scalar(node).encode('ascii')
      rescue UnicodeEncodeError => exc
        raise ConstructorError.new(
          nil,
          nil,
          _F('failed to convert base64 data into ascii: {exc!s}', exc=exc),
          node.start_mark,
          )
      end
      begin
        return Base64.decodebytes(value)
      rescue binascii.Error => exc
        raise ConstructorError.new(
          nil,
          nil,
          _F('failed to decode base64 data: {exc!s}', exc=exc),
          node.start_mark,
          )
      end
    end

    alias :construct_python_long :construct_yaml_int

    def construct_python_complex(node)
      Complex.new(construct_scalar(node))
    end

    def construct_python_tuple(node)
      Array(construct_sequence(node))
    end

    # def find_python_module(name, mark)
    #     if not name
    #         raise ConstructorError.new(
    #             'while constructing a Python module',
    #             mark,
    #             'expected non-empty name appended to the tag',
    #             mark,
    #         )
    #     try
    #         __import__(name)
    #     rescue ImportError as exc
    #         raise ConstructorError.new(
    #             'while constructing a Python module',
    #             mark,
    #             _F('cannot find module {name!r} ({exc!s})', name=name, exc=exc),
    #             mark,
    #         )
    #     return sys.modules[name]

    def find_python_name(name, mark)
      unless name
        raise ConstructorError.new(
          'while constructing a Python object',
          mark,
          'expected non-empty name appended to the tag',
          mark,
          )
      end
      if name.include?('.')
        lname = name.split('.')
        lmodule_name = lname
        lobject_name = []
        while lmodule_name.size > 1
          lobject_name.insert(0, lmodule_name.pop)
          module_name = lmodule_name.join('.')
          begin
            require module_name
            break
          rescue LoadError
            continue
          end
        end
      else
        module_name = builtins_module
        lobject_name = [name]
      end
      begin
        require module_name
      rescue LoadError => exc
        raise ConstructorError.new(
          'while constructing a Python object',
          mark,
          _F(
            'cannot find module {module_name!r} ({exc!s})',
            module_name=module_name,
            exc=exc,
            ),
          mark,
          )
      end
      the_module = sys.modules[module_name]
      object_name = lobject_name.join('.')
      obj = the_module
      until lobject_name.empty?
        unless obj.respond_to?)lobject_name[0])
        raise ConstructorError.new(
          'while constructing a Python object',
          mark,
          _F(
            'cannot find {object_name!r} in the module {module_name!r}',
            object_name=object_name,
            module_name = the_module.__name__,
            ),
          mark,
          )
        end
        obj = getattr(obj, lobject_name.pop(0))
      end
      obj
    end

    def construct_python_name(suffix, node)
      value = construct_scalar(node)
      if value
        raise ConstructorError.new(
          'while constructing a Python name',
          node.start_mark,
          _F('expected the empty value, but found {value!r}', value=value),
          node.start_mark,
          )
      end
      find_python_name(suffix, node.start_mark)
    end

    def construct_python_module(suffix, node)
      value = construct_scalar(node)
      if value
        raise ConstructorError.new(
          'while constructing a Python module',
          node.start_mark,
          _F('expected the empty value, but found {value!r}', value=value),
          node.start_mark,
          )
      end
      find_python_module(suffix, node.start_mark)
    end

    def make_python_instance(suffix, node, args = nil, kwds = nil, newobj = false)
      args ||= []
      kwds ||= {}
      cls = find_python_name(suffix, node.start_mark)
      if newobj && cls.instance_of?(type)
        cls.new(*args, **kwds)
      else
        return cls.new(*args, **kwds)
      end
    end

    # def set_python_instance_state(instance, state)
    #     if hasattr(instance, '__setstate__')
    #         instance.__setstate__(state)
    #     else
    #         slotstate = {}  # type: Dict[Any, Any]
    #         if isinstance(state, tuple) and len(state) == 2
    #             state, slotstate = state
    #         if hasattr(instance, '__dict__')
    #             instance.__dict__.update(state)
    #         elsif state
    #             slotstate.update(state)
    #         for key, value in slotstate.items()
    #             setattr(instance, key, value)

    # def construct_python_object(suffix, node)
    #     # Format
    #     #   !!python/object:module.name { ... state ... }
    #     instance = make_python_instance(suffix, node, true)
    #     @recursive_objects[node] = instance
    #     yield instance
    #     deep = hasattr(instance, '__setstate__')
    #     state = construct_mapping(node, deep=deep)
    #     set_python_instance_state(instance, state)

    # def construct_python_object_apply(suffix, node, newobj=false)
    #     # type: (Any, Any, bool) -> Any
    #     # Format
    #     #   !!python/object/apply       # (or !!python/object/new)
    #     #   args: [ ... arguments ... ]
    #     #   kwds: { ... keywords ... }
    #     #   state: ... state ...
    #     #   listitems: [ ... listitems ... ]
    #     #   dictitems: { ... dictitems ... }
    #     # or short format
    #     #   !!python/object/apply [ ... arguments ... ]
    #     # The difference between !!python/object/apply and !!python/object/new
    #     # is how an object is created, check make_python_instance for details.
    #     if isinstance(node, SequenceNode)
    #         args = construct_sequence(node, deep=true)
    #         kwds = {}  # type: Dict[Any, Any]
    #         state = {}  # type: Dict[Any, Any]
    #         listitems = []  # type: List[Any]
    #         dictitems = {}  # type: Dict[Any, Any]
    #     else
    #         value = construct_mapping(node, deep=true)
    #         args = value.get('args', [])
    #         kwds = value.get('kwds', {})
    #         state = value.get('state', {})
    #         listitems = value.get('listitems', [])
    #         dictitems = value.get('dictitems', {})
    #     instance = make_python_instance(suffix, node, args, kwds, newobj)
    #     if bool(state)
    #         set_python_instance_state(instance, state)
    #     if bool(listitems)
    #         instance.extend(listitems)
    #     if bool(dictitems)
    #         for key in dictitems
    #             instance[key] = dictitems[key]
    #     return instance
    #
    # def construct_python_object_new(suffix, node)
    #     # type: (Any, Any) -> Any
    #     return construct_python_object_apply(suffix, node, newobj=true)
  end

  Constructor.add_constructor('tag:yaml.org,2002:python/none', Constructor.method(:construct_yaml_null))

  Constructor.add_constructor('tag:yaml.org,2002:python/bool', Constructor.method(:construct_yaml_bool))

  Constructor.add_constructor('tag:yaml.org,2002:python/str', Constructor.method(:construct_python_str))

  Constructor.add_constructor('tag:yaml.org,2002:python/unicode', Constructor.method(:construct_python_unicode))

  Constructor.add_constructor('tag:yaml.org,2002:python/bytes', Constructor.method(:construct_python_bytes))

  Constructor.add_constructor('tag:yaml.org,2002:python/int', Constructor.method(:construct_yaml_int))

  Constructor.add_constructor('tag:yaml.org,2002:python/long', Constructor.method(:construct_python_long))

  Constructor.add_constructor('tag:yaml.org,2002:python/float', Constructor.method(:construct_yaml_float))

  Constructor.add_constructor('tag:yaml.org,2002:python/complex', Constructor.method(:construct_python_complex))

  Constructor.add_constructor('tag:yaml.org,2002:python/list', Constructor.method(:construct_yaml_seq), true)

  Constructor.add_constructor('tag:yaml.org,2002:python/tuple', Constructor.method(:construct_python_tuple))

  Constructor.add_constructor('tag:yaml.org,2002:python/dict', Constructor.method(:construct_yaml_map), true)

  Constructor.add_multi_constructor('tag:yaml.org,2002:python/name:', Constructor.method(:construct_python_name))

  Constructor.add_multi_constructor('tag:yaml.org,2002:python/module:', Constructor.method(:construct_python_module))

  Constructor.add_multi_constructor('tag:yaml.org,2002:python/object:', Constructor.method(:construct_python_object), true)

  Constructor.add_multi_constructor('tag:yaml.org,2002:python/object/apply:', Constructor.method(:construct_python_object_apply))

  Constructor.add_multi_constructor('tag:yaml.org,2002:python/object/new:', Constructor.method(:construct_python_object_new))


  class RoundTripConstructor < SafeConstructor
    "need to store the comments on the node itself,
    as well as on the items
    "

    def comment(idx)
      raise unless @loader.comment_handling
      x = scanner.comments[idx]
      x.set_assigned
      x
    end

    def comments(list_of_comments, idx = nil)
      # hand in the comment and optional pre, eol, post segment
      return [] if list_of_comments.nil?
      unless idx.nil?
        return [] if list_of_comments[idx].nil?

        list_of_comments = list_of_comments[idx]
      end
      list_of_comments.each { |x| yield comment(x) }
    end

    def construct_scalar(node)
      unless node.instance_of?(ScalarNode)
        raise ConstructorError.new(
          nil,
          nil,
          _F('expected a scalar node, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end

      if node.style == '|' && node.value.instance_of?(String)
        lss = LiteralScalarString(node.value, node.anchor)
        if @loader && @loader.comment_handling.nil?
          if node.comment && node.comment[1]
            lss.comment = node.comment[1][0]
          end
        else
          # NEWCMNT
          if node&.comment[1]
            # nprintf('>>>>nc1', node.comment)
            # EOL comment after |
            lss.comment = comment(node.comment[1][0])
          end
        end
        return lss
      end
      if node.style == '>' && node.value.instance_of?(String)
        fold_positions = []
        idx = -1
        loop do
          idx = node.value[(idx + 1)..-1]).index("\a")
          break unless idx
          fold_positions.append(idx - fold_positions.size)
        end
        fss = FoldedScalarString(node.value.gsub("\a", ''), node.anchor)
        if @loader && @loader.comment_handling.nil?
          if node&.comment[1]
            fss.comment = node.comment[1][0]
          end
        else
          # NEWCMNT
          if !node.comment.nil? && node.comment[1]
            # nprintf('>>>>nc2', node.comment)
            # EOL comment after >
            fss.comment = comment(node.comment[1][0])
          end
        end
        fss.fold_pos = fold_positions unless fold_positions.empty?
        return fss
      elsif @preserve_quotes.to_boolean && node.value.instance_of?(String)
        return SingleQuotedScalarString(node.value, node.anchor) if node.style == "'"

        return DoubleQuotedScalarString(node.value, anchor=node.anchor) if node.style == '"'
      end
      return PlainScalarString(node.value, anchor=node.anchor) if node.anchor

      node.value
    end

    def construct_yaml_int(node)
      width = nil
      value_su = construct_scalar(node)
      begin
        while value_su[-1] == '_'
          value_su.chomp!('_')
        end
        sx = value_su
        underscore = [sx.size - sx.rindex('_') - 1, false, false]
      rescue ValueError
        underscore = nil
      rescue IndexError
        underscore = nil
      end
      value_s = value_su.gsub('_', '')
      sign = 1
      case value_s[0]
        when '-'
          sign = -1
        when '+-'
          value_s = value_s[1..-1]
      end
      return 0 if value_s == '0'

      if value_s.start_with?('0b')
        if resolver.processing_version > [1, 1] && value_s[2] == '0'
          width = value_s[2..-1].size
        end
        if underscore
          underscore[1] = value_su[2] == '_'
          underscore[2] = value_su[2..-1].size > 1 && value_su[-1] == '_'
        end
        return BinaryInt.new(
          sign * value_s[2..-1].to_i(2),
          width,
          underscore,
          node.anchor
        )
      elsif value_s.start_with?('0x')
        # default to lower-case if no a-fA-F in string
        if resolver.processing_version > [1, 1] && value_s[2] == '0'
          width = value_s[2..-1].size
        end
        hex_fun = HexInt
        value_s[2..-1].each do |ch|
          if 'ABCDEF'.include?(ch)  # first non-digit is capital
            hex_fun = HexCapsInt
            break
          end
          break if 'abcdef'.include?(ch)
        end
        if underscore
          underscore[1] = value_su[2] == '_'
          underscore[2] = value_su[2..-1].size > 1 && value_su[-1] == '_'
        end
        return hex_fun.new(
          sign * value_s[2..-1].to_i(16),
          width,
          underscore,
          node.anchor
        )
      elsif value_s.start_with?('0o')
        if resolver.processing_version > [1, 1] && value_s[2] == '0'
          width = value_s[2..-1].size
        end
        if underscore
          underscore[1] = value_su[2] == '_'
          underscore[2] = len(value_su[2..-1]) > 1 && value_su[-1] == '_'
        end
        return OctalInt.new(
          sign * value_s[2:].to_i(8),
          width,
            underscore,
            node.anchor
        )
      elsif resolver.processing_version != [1, 2] && value_s[0] == '0'
        return OctalInt.new(
          sign * value_s.to_i(8),
          width,
          underscore,
          node.anchor
        )
      elsif resolver.processing_version != [1, 2] && value_s.include?(':')
        digits = value_s.split(':').map(&:to_i)
        digits.reverse
        base = 1
        value = 0
        digit digits.each do |digit|
          value += digit * base
          base *= 60
        end
        return sign * value
      elsif resolver.processing_version > [1, 1] && value_s[0] == '0'
        # not an octal, an integer with leading zero(s)
        if underscore
          # cannot have a leading underscore
          underscore[2] = value_su.size > 1 && value_su[-1] == '_'
        end
        return ScalarInt.new(sign * value_s.to_i, value_s.size, underscore)
      elsif underscore
        # cannot have a leading underscore
        underscore[2] = value_su.size > 1 && value_su[-1] == '_'
        return ScalarInt.new(sign * value_s.to_i, nil, underscore, node.anchor)
      elsif node.anchor
        return ScalarInt.new(sign (value_s.to_i, nil, underscore, node.anchor)
      else
        return sign * value_s.to_i
      end
    end

    def leading_zeros(v)
      lead0 = 0
      idx = 0
      while idx < v.size && '0.'.include?(v[idx])
        lead0 += 1 if v[idx] == '0'
        idx += 1
      end
      lead0
    end
    include Serializer

    def construct_yaml_float(node)
      # underscore = nil
      m_sign = false
      value_so = construct_scalar(node)
      value_s = value_so.gsub('_', '').downcase
      sign = 1
      case value_s[0]
        when '-'
          sign = -1
        when '+-'
          m_sign = value_s[0]
          value_s = value_s[1..-1]
      end
      return sign * inf_value if value_s == '.inf'

      return nan_value if value_s == '.nan'

      if resolver.processing_version != [1, 2] && value_s.include(':')
        digits = value_s.split(':').map(&to_f)
        digits.reverse
        base = 1
        value = 0.0
        digits.each do |digit|
          value += digit * base
          base *= 60
        end
        return sign * value
      end
      if value_s.include?('e')
        mantissa, exponent = value_so.split('e')
        if exponent
          exp = 'e'
        else
          mantissa, exponent = value_so.split('E')
          exp = 'E'
        end
        if resolver.processing_version != [1, 2]
          # value_s is lower case independent of input
          unless mantissa.include?('.')
            warnings.warn(MantissaNoDotYAML1_1Warning(node, value_so))
          end
        end
        lead0 = leading_zeros(mantissa)
        width = mantissa.size
        prec = mantissa.index('.')
        width -= 1 if m_sign
        e_width = exponent.size
        e_sign = '+-'.include?(exponent[0])
        # nprint('sf', width, prec, m_sign, exp, e_width, e_sign)
        return ScalarFloat.new(
          sign * float(value_s),
          width,
          prec,
          m_sign,
          lead0,
          exp,
          e_width,
          e_sign,
          node.anchor
        )
      end
      width = value_so.size
      prec = value_so.index('.')  # you can use index, this would not be float without dot
      lead0 = leading_zeros(value_so)
      return ScalarFloat.new(
        sign * float(value_s),
        width,
        prec,
        m_sign,
        lead0,
        node.anchor
      )
    end

    alias :construct_yaml_str :construct_scalar

    def construct_rt_sequence(node, seqtyp, deep = false)
      unless node.instance_of?(SequenceNode)
        raise ConstructorError.new(
          nil,
          nil,
          _F('expected a sequence node, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end
      ret_val = []
      if @loader && @loader.comment_handling.nil?
        if node.comment
          seqtyp._yaml_add_comment(node.comment[0..2])
          if node.comment.size > 2
            # this happens e.g. if you have a sequence element that is a flow-style
            # mapping and that has no EOL comment but a following commentline or
            # empty line
            seqtyp.yaml_end_comment_extend(node.comment[2], true)
          end
        end
      else
        # NEWCMNT
        # if node.comment
        #     nprintf('nc3', node.comment)
      end
      if node.anchor
        seqtyp.yaml_set_anchor(node.anchor) unless templated_id(node.anchor)
      end
      node.value.each_with_index do |child, idx|
        if child.comment
          seqtyp._yaml_add_comment(child.comment, key=idx)
          child.comment = nil  # if moved to sequence remove from child
        end
        ret_val.append(construct_object(child, deep))
        seqtyp._yaml_set_idx_line_col(
          idx, [child.start_mark.line, child.start_mark.column]
        )
      end
      ret_val
    end

    def constructed(value_node)
      # If the contents of a merge are defined within the
      # merge marker, then they won't have been constructed
      # yet. But if they were already constructed, we need to use
      # the existing object.
      if @constructed_objects.include?(value_node)
        value = @constructed_objects[value_node]
      else
        value = construct_object(value_node, false)
      end
      value
    end

    def flatten_mapping(node)
      "
        This implements the merge key feature http://yaml.org/type/merge.html
        by inserting keys from the merge dict/list of dicts if not yet
        available in this node
        "

      # merge = []
      merge_map_list = []
      index = 0
      while index < node.value.size
        key_node, value_node = node.value[index]
        if key_node.tag == 'tag:yaml.org,2002:merge'
          if merge_map_list
            args = [
              'while constructing a mapping',
              node.start_mark,
              'found duplicate key "{}"'.format(key_node.value),
              key_node.start_mark
            ]
            raise DuplicateKeyError.new(*args)
          end
          node.value.delete(index)
          if value_node.instance_of?(MappingNode)
            merge_map_list.append((index, constructed(value_node)))
            # flatten_mapping(value_node)
            # merge.extend(value_node.value)
          elsif value_node.instance_of?(SequenceNode)
            # submerge = []
            value_node.value.each do |subnode|
              unless subnode.instance_of?(MappingNode)
                raise ConstructorError.new(
                  'while constructing a mapping',
                  node.start_mark,
                  _F(
                    'expected a mapping for merging, but found {subnode_id!s}',
                    subnode_id=subnode.id,
                    ),
                  subnode.start_mark,
                  )
              end
              merge_map_list.append((index, constructed(subnode)))
            end
            #     flatten_mapping(subnode)
            #     submerge.append(subnode.value)
            # submerge.reverse()
            # for value in submerge
            #     merge.extend(value)
          else
            raise ConstructorError.new(
              'while constructing a mapping',
              node.start_mark,
              _F(
                'expected a mapping or list of mappings for merging, '
            'but found {value_node_id!s}',
              value_node_id=value_node.id,
            ),
              value_node.start_mark,
            )
          end
        elsif key_node.tag == 'tag:yaml.org,2002:value'
          key_node.tag = 'tag:yaml.org,2002:str'
          index += 1
        else
          index += 1
        end
        merge_map_list
        # if merge
        #     node.value = merge + node.value
      end
    end

    def _sentinel
    end

    def construct_mapping(node, maptyp, deep = false)
      unless node.instance_of?(MappingNode)
        raise ConstructorError.new(
          nil,
          nil,
          _F('expected a mapping node, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end
      merge_map = flatten_mapping(node)
      # mapping = {}
      if @loader && @loader.comment_handling.nil?
        if node.comment
          maptyp._yaml_add_comment(node.comment[0..2])
          if node.comment.size > 2
            maptyp.yaml_end_comment_extend(node.comment[2], true)
          end
        end
      else
        # NEWCMNT
        if node.comment
          # nprintf('nc4', node.comment, node.start_mark)
          maptyp.ca.pre ||= []
          comments(node.comment, 0).each { |cmnt| maptyp.ca.pre.append(cmnt) }
        end
      end

      if node.anchor
        maptyp.yaml_set_anchor(node.anchor) unless templated_id(node.anchor)
      end
      last_key, last_value = nil, _sentinel
      node.value.each do |key_node, value_node|
        # keys can be list -> deep
        key = construct_object(key_node, true)
        # lists are not hashable, but tuples are
        # if not isinstance(key, Hashable)
        #     if isinstance(key, MutableSequence)
        #         key_s = CommentedKeySeq(key)
        #         if key_node.flow_style is true
        #             key_s.fa.set_flow_style()
        #         elsif key_node.flow_style is false
        #             key_s.fa.set_block_style()
        #         end
        #         key = key_s
        #     elsif isinstance(key, MutableMapping)
        #         key_m = CommentedKeyMap(key)
        #         if key_node.flow_style is true
        #             key_m.fa.set_flow_style()
        #         elsif key_node.flow_style is false
        #             key_m.fa.set_block_style()
        #         end
        #         key = key_m
        #     end
        # end
        # if not isinstance(key, Hashable)
        #     raise ConstructorError.new(
        #         'while constructing a mapping',
        #         node.start_mark,
        #         'found unhashable key',
        #         key_node.start_mark,
        #     )
        # end
        value = construct_object(value_node, deep)
        if check_mapping_key(node, key_node, maptyp, key, value)
          if @loader && @loader.comment_handling.nil?
            if key_node.comment && key_node.comment.size > 4 && key_node.comment[4]
              if last_value.nil?
                key_node.comment[0] = key_node.comment.delete_at(4)
                maptyp._yaml_add_comment(key_node.comment, last_key)
              else
                key_node.comment[2] = key_node.comment.delete_at(4)
                maptyp._yaml_add_comment(key_node.comment, key)
              end
              key_node.comment = nil
            end
            maptyp._yaml_add_comment(key_node.comment, :key => key) if key_node.comment
            maptyp._yaml_add_comment(value_node.comment, :value => key) if value_node.comment
          else
            # NEWCMNT
            if key_node.comment
              # nprintf('nc5a', key, key_node.comment)
              maptyp.ca.set(key, C_KEY_PRE, key_node.comment[0]) if key_node.comment[0]
              maptyp.ca.set(key, C_KEY_EOL, key_node.comment[1]) if key_node.comment[1]
              maptyp.ca.set(key, C_KEY_POST, key_node.comment[2]) if key_node.comment[2]
            end
            if value_node.comment
              # nprintf('nc5b', key, value_node.comment)
              maptyp.ca.set(key, C_VALUE_PRE, value_node.comment[0]) if value_node.comment[0]
              maptyp.ca.set(key, C_VALUE_EOL, value_node.comment[1]) if value_node.comment[1]
              maptyp.ca.set(key, C_VALUE_POST, value_node.comment[2]) if value_node.comment[2]
            end
          end
          maptyp._yaml_set_kv_line_col(
            key,
            [
              key_node.start_mark.line,
              key_node.start_mark.column,
              value_node.start_mark.line,
              value_node.start_mark.column
            ]
          )
          maptyp[key] = value
          last_key, last_value = key, value  # could use indexing
        end
        # do this last, or <<: before a key will prevent insertion in instances
        # of collections.OrderedDict (as they have no __contains__
        maptyp.add_yaml_merge(merge_map) if merge_map
      end
    end

    def construct_setting(node, typ, deep = false)
      unless node.instance_of?(MappingNode)
        raise ConstructorError.new(
          nil,
          nil,
          _F('expected a mapping node, but found {node_id!s}', node_id=node.id),
          node.start_mark,
          )
      end
      if @loader && @loader.comment_handling.nil?
        if node.comment
          typ._yaml_add_comment(node.comment[0..2])
          if node.comment.size > 2
            typ.yaml_end_comment_extend(node.comment[2], clear=true)
          end
        end
      else
        # NEWCMNT
        # if node.comment
        #     nprintf('nc6', node.comment)
      end

      if node.anchor
        typ.yaml_set_anchor(node.anchor) unless templated_id(node.anchor)
      end
      node.value.each do |key_node, value_node|
        # keys can be list -> deep
        key = construct_object(key_node, true)
        # lists are not hashable, but tuples are
        # if not isinstance(key, Hashable)
        #     if isinstance(key, list)
        #         key = tuple(key)
        # if not isinstance(key, Hashable)
        #     raise ConstructorError.new(
        #         'while constructing a mapping',
        #         node.start_mark,
        #         'found unhashable key',
        #         key_node.start_mark,
        #     )
        # construct but should be null
        value = construct_object(value_node, deep)
        check_set_key(node, key_node, typ, key)
        if @loader && @loader.comment_handling.nil?
          typ._yaml_add_comment(key_node.comment, :key => key) if key_node.comment
          typ._yaml_add_comment(value_node.comment, :value => key) if value_node.comment
        else
          # NEWCMNT
          # if key_node.comment
          #     nprintf('nc7a', key_node.comment)
          # if value_node.comment
          #     nprintf('nc7b', value_node.comment)
        end
        typ.add(key)
      end
    end

    def construct_yaml_seq(node)
      data = CommentedSeq.new
      data._yaml_set_line_col(node.start_mark.line, node.start_mark.column)
      # if node.comment
      #    data._yaml_add_comment(node.comment)
      yield data
      data.merge(construct_rt_sequence(node, data))
      set_collection_style(data, node)
    end

    def construct_yaml_map(node)
      data = CommentedMap.new
      data._yaml_set_line_col(node.start_mark.line, node.start_mark.column)
      yield data
      construct_mapping(node, data, true)
      set_collection_style(data, node)
    end

    def set_collection_style(data, node)
      return if data.empty?

      if node.flow_style
        data.fa.set_flow_style
      else
        data.fa.set_block_style
      end
    end

    # def construct_yaml_object(node, cls)
    #     data = cls.new
    #     yield data
    #     if hasattr(data, '__setstate__')
    #         state = SafeConstructor.construct_mapping(node, deep=true)
    #         data.__setstate__(state)
    #     else
    #         state = SafeConstructor.construct_mapping(node)
    #         if hasattr(data, '__attrs_attrs__'):  # issue 394
    #             data.__init__(**state)
    #         else
    #             data.__dict__.update(state)
    #     if node.anchor
    #         from ruamel.yaml.serializer import templated_id
    #         from ruamel.yaml.anchor import Anchor
    #
    #         if not templated_id(node.anchor)
    #             if not hasattr(data, Anchor.attrib)
    #                 a = Anchor()
    #                 setattr(data, Anchor.attrib, a)
    #             else
    #                 a = getattr(data, Anchor.attrib)
    #             a.value = node.anchor

    def construct_yaml_omap(node)
      # Note: we do now check for duplicate keys
      omap = CommentedOrderedMap.new
      omap._yaml_set_line_col(node.start_mark.line, node.start_mark.column)
      if node.flow_style
        omap.fa.set_flow_style
      else
        omap.fa.set_block_style
      end
      yield omap
      if @loader && @loader.comment_handling.nil?
        if node.comment
          omap._yaml_add_comment(node.comment[0..2])
          omap.yaml_end_comment_extend(node.comment[2], true) if node.comment.size > 2
        end
      else
        # NEWCMNT
        # if node.comment
        #     nprintf('nc8', node.comment)
        unless node.instance_of?(SequenceNode)
          raise ConstructorError.new(
            'while constructing an ordered map',
            node.start_mark,
            _F('expected a sequence, but found {node_id!s}', node_id=node.id),
            node.start_mark,
            )
        end
        node.value.each do |subnode|
          unless subnode.instance_of?(MappingNode)
            raise ConstructorError.new(
              'while constructing an ordered map',
              node.start_mark,
              _F(
                'expected a mapping of length 1, but found {subnode_id!s}',
                subnode_id=subnode.id,
                ),
              subnode.start_mark,
              )
          end
          if subnode.value.size != 1
            raise ConstructorError.new(
              'while constructing an ordered map',
              node.start_mark,
              _F(
                'expected a single mapping item, but found {len_subnode_val:d} items',
                len_subnode_val=len(subnode.value),
                ),
              subnode.start_mark,
              )
          end
          key_node, value_node = subnode.value[0]
          key = construct_object(key_node)
          raise if omap.include?(key)
          value = construct_object(value_node)
          if @loader && @loader.comment_handling.nil?
            omap._yaml_add_comment(key_node.comment, :key => key) if key_node.comment
            omap._yaml_add_comment(subnode.comment, :key => key) if subnode.comment
            omap._yaml_add_comment(value_node.comment, :value => key) if value_node.comment
          else
            # NEWCMNT
            # if key_node.comment
            #     nprintf('nc9a', key_node.comment)
            # if subnode.comment
            #     nprintf('nc9b', subnode.comment)
            # if value_node.comment
            #     nprintf('nc9c', value_node.comment)
          end
          omap[key] = value
        end
      end
    end

    def construct_yaml_set(node)
      data = CommentedSet.new
      data._yaml_set_line_col(node.start_mark.line, node.start_mark.column)
      yield data
      construct_setting(node, data)
    end

    def construct_undefined(node)
      begin
        if node.instance_of?(MappingNode)
          data = CommentedMap.new
          data._yaml_set_line_col(node.start_mark.line, node.start_mark.column)
          if node.flow_style
            data.fa.set_flow_style
          else
            data.fa.set_block_style
          end
          data.yaml_set_tag(node.tag)
          yield data

          if node.anchor
            data.yaml_set_anchor(node.anchor) unless templated_id(node.anchor)
          end
          construct_mapping(node, data)
          return
        elsif node.instance_of?(ScalarNode)
          data2 = TaggedScalar.new
          data2.value = construct_scalar(node)
          data2.style = node.style
          data2.yaml_set_tag(node.tag)
          yield data2

          if node.anchor
            data2.yaml_set_anchor(node.anchor, true) unless templated_id(node.anchor)
          end
          return
        elsif node.instance_of?(SequenceNode)
          data3 = CommentedSeq.new
          data3._yaml_set_line_col(node.start_mark.line, node.start_mark.column)
          if node.flow_style
            data3.fa.set_flow_style
          else
            data3.fa.set_block_style
          end
          data3.yaml_set_tag(node.tag)
          yield data3

          if node.anchor
            data3.yaml_set_anchor(node.anchor) unless templated_id(node.anchor)
          end
          data3.extend(construct_sequence(node))
          return
        end
      rescue
      end
      raise ConstructorError.new(
        nil,
        nil,
        _F(
          'could not determine a constructor for the tag {node_tag!r}', node_tag=node.tag
        ),
        node.start_mark,
        )
    end

    def construct_yaml_timestamp(node, values = nil)
      begin
        match = TIMESTAMP_REGEXP.match(node.value)
      rescue TypeError
        match = nil
      end
      unless match
        raise ConstructorError.new(
          nil,
          nil,
          'failed to construct timestamp from "{}"'.format(node.value),
          node.start_mark,
          )
      end
      values = match.named_captures
      return create_timestamp(**values) unless values['hour']
      # return SafeConstructor.construct_yaml_timestamp(node, values)
      found = false
      %w[t tz_sign tz_hour tz_minute].each do |part|
        if values[part]
          found = true
          break
        end
      end
      return create_timestamp(**values) unless found
      # return SafeConstructor.construct_yaml_timestamp(node, values)
      dd = create_timestamp(**values)  # this has delta applied
      delta = nil
      if values['tz_sign']
        tz_hour = values['tz_hour'].to_i
        minutes = values['tz_minute']
        tz_minute = minutes.to_i #if minutes else 0
        delta = datetime.timedelta(hours=tz_hour, minutes=tz_minute)
        delta = -delta if values['tz_sign'] == '-'
      end
      # should check for nil and solve issue 366 should be tzinfo=delta)
      data = TimeStamp.new(
        dd.year, dd.month, dd.day, dd.hour, dd.minute, dd.second, dd.microsecond
      )
      if delta
        data._yaml['delta'] = delta
        tz = values['tz_sign'] + values['tz_hour']
        tz += ':' + values['tz_minute'] if values['tz_minute']
        data._yaml['tz'] = tz
      else
        data._yaml['tz'] = values['tz'] if values['tz']  # no delta
      end

      data._yaml['t'] = true if values['t']
      data
    end

    def construct_yaml_bool(node)
      b = SafeConstructor.construct_yaml_bool(node)
      return ScalarBoolean.new(b, node.anchor) if node.anchor

      b
    end
  end

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:null', RoundTripConstructor.method(:construct_yaml_null))

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:bool', RoundTripConstructor.method(:construct_yaml_bool))

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:int', RoundTripConstructor.method(:construct_yaml_int))

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:float', RoundTripConstructor.method(:construct_yaml_float))

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:binary', RoundTripConstructor.method(:construct_yaml_binary))

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:timestamp', RoundTripConstructor.method(:construct_yaml_timestamp))

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:omap', RoundTripConstructor.method(:construct_yaml_omap), true)

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:pairs', RoundTripConstructor.method(:construct_yaml_pairs), true)

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:set', RoundTripConstructor.method(:construct_yaml_set), true)

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:str', RoundTripConstructor.method(:construct_yaml_str))

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:seq', RoundTripConstructor.method(:construct_yaml_seq), true)

  RoundTripConstructor.add_constructor('tag:yaml.org,2002:map', RoundTripConstructor.method(:construct_yaml_map), true)

  RoundTripConstructor.add_constructor('NULL TAG', RoundTripConstructor.method(:construct_undefined), true)
end
