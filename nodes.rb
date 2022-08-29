# encoding: utf-8

# frozen_string_literal: true

# import sys
# 
# from ruamel.yaml.compat import _F

require 'compat'

module SweetStreetYaml
  class Node
    attr_accessor :tag, :value, :start_mark, :end_mark, :comment, :anchor

    def initialize(tag, value, start_mark, end_mark, comment: nil, anchor: nil)
      @tag = tag
      @value = value
      @start_mark = start_mark
      @end_mark = end_mark
      @comment = comment
      @anchor = anchor
    end
    
    def to_s
        value = @value.to_s
        return _F(
            '{class_name!s}(tag={self_tag!r}, value={value!s})',
            class_name=__class__.__name__,
            self_tag=tag,
            value=value,
        )
    end

    def dump(indent = 0)
      if @value.instance_of?(String)
        sys.stdout.write(
          '{}{}(tag={!r}, value={!r})\n'.format(
            '  ' * indent, __class__.__name__, tag, value
          )
        )
        sys.stdout.write('    {}comment: {})\n'.format('  ' * indent, comment)) if @comment
        return
      end
      sys.stdout.write(
        '{}{}(tag={!r})\n'.format('  ' * indent, __class__.__name__, tag)
      )
      sys.stdout.write('    {}comment: {})\n'.format('  ' * indent, comment)) if @comment
      @value.each do |k|
        case v.class
          when 'Array'
            v.each { |v1| v1.dump(indent + 1) }
          when 'Node'
            v.dump(indent + 1)
          else
            sys.stdout.write('Node value type? {}\n'.format(type(v)))
        end
      end
    end
  end


  class ScalarNode < Node
    "
    styles
      ? -> set() ? key, no value
      \" -> double quoted
      ' -> single quoted
      | -> literal style
      > -> folding style
    "

    attr_accessor :style
    @id = 'scalar'

    def initialize(
      tag, value, start_mark: nil, end_mark: nil, style: nil, comment: nil, anchor: nil
    )
      super(tag, value, start_mark, end_mark, :comment => comment, :anchor => anchor)
      @style = style
    end
  end


  class CollectionNode < Node
    attr_accessor :flow_style

    def initialize(
      tag,
      value,
      start_mark: nil,
      end_mark: nil,
      flow_style: nil,
      comment: nil,
      anchor: nil
    )
      super(tag, value, start_mark, end_mark, :comment => comment)
      @flow_style = flow_style
      @anchor = anchor
    end
  end


  class SequenceNode < CollectionNode
    @id = 'sequence'
  end


  class MappingNode < CollectionNode
    attr_accessor :merge
    @id = 'mapping'

    def initialize(
      tag,
      value,
      start_mark: nil,
      end_mark: nil,
      flow_style: nil,
      comment: nil,
      anchor: nil
    )
      super
      @merge = nil
    end
  end
end
