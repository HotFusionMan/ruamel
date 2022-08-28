# encoding: utf-8

# frozen_string_literal: true

# import warnings
#
# from ruamel.yaml.error import MarkedYAMLError, ReusedAnchorWarning
# from ruamel.yaml.compat import _F, nprint, nprintf  # NOQA
#
# from ruamel.yaml.events import (
#     StreamStartEvent,
#     StreamEndEvent,
#     MappingStartEvent,
#     MappingEndEvent,
#     SequenceStartEvent,
#     SequenceEndEvent,
#     AliasEvent,
#     ScalarEvent,
# )
# from ruamel.yaml.nodes import MappingNode, ScalarNode, SequenceNode

require 'compat'
require 'error'
require 'events'
require 'nodes'

module SweetStreeYaml
  class ComposerError < MarkedYAMLError
  end


  class Composer
    def initialize(loader = nil)
      @loader = loader
      @loader._composer = self if @loader && @loader.instance_variable_get(:@_composer).nil?
      @anchors = {}
    end

    def parser
      return(@parser) if defined?(@parser)

      @parser =
        if @loader.instance_variable_get(:@typ)
          @loader.parser
        else
          @loader._parser
        end
    end

    def resolver
      return @loader.resolver if @loader.instance_variable_get(:@typ)

      @loader._resolver
    end

    def check_node
      # Drop the STREAM-START event.
      parser.get_event if parser.check_event(StreamStartEvent)

      # If there are more documents available?
      parser.check_event(StreamEndEvent)
    end
    
    def get_node
      # Get the root node of the next document.
      compose_document unless parser.check_event(StreamEndEvent)
    end

    def get_single_node
      # Drop the STREAM-START event.
      parser.get_event

      # Compose a document if the stream is not empty.
      document = nil
      document = compose_document unless parser.check_event(StreamEndEvent)

      # Ensure that the stream contains no more documents.
      unless parser.check_event(StreamEndEvent)
        event = parser.get_event
        raise ComposerError.new(
          'expected a single document in the stream',
          document.start_mark,
          'but found another document',
          event.start_mark,
          )
      end

      # Drop the STREAM-END event.
      parser.get_event

      document
    end

    def compose_document
      # Drop the DOCUMENT-START event.
      parser.get_event

      # Compose the root node.
      node = compose_node(nil, nil)

      # Drop the DOCUMENT-END event.
      parser.get_event

      @anchors = {}
      node
    end

    def return_alias(a)
      a
    end

    def compose_node(parent, index)
      if parser.check_event(AliasEvent)
        event = parser.get_event
        alias = event.anchor
        unless @anchors.has_key?(alias)
        raise ComposerError.new(
          nil,
          nil,
          _F('found undefined alias {alias!r}', alias=alias),
          event.start_mark,
        )
        end
        return_alias(@anchors[alias])
      end
      event = parser.peek_event
      anchor = event.anchor
      if anchor   # have an anchor
        if @anchors.has_key?(anchor)
          ws = (
          "\nfound duplicate anchor {!r}\nfirst occurrence {}\nsecond occurrence "
          '{}'.format((anchor), anchors[anchor].start_mark, event.start_mark)
          )
        end
        logger.warn(ws, ReusedAnchorWarning)
      end
      resolver.descend_resolver(parent, index)
      if parser.check_event(ScalarEvent)
        node = compose_scalar_node(anchor)
      elsif parser.check_event(SequenceStartEvent)
        node = compose_sequence_node(anchor)
      elsif parser.check_event(MappingStartEvent)
        node = compose_mapping_node(anchor)
      end
      resolver.ascend_resolver
      node
    end

    def compose_scalar_node(anchor)
      event = parser.get_event
      tag = event.tag
      tag = resolver.resolve(ScalarNode, event.value, event.implicit) if tag.nil? || tag == '!'
      node = ScalarNode.new(
        tag,
        event.value,
        event.start_mark,
        event.end_mark,
        :style => event.style,
        :comment => event.comment,
        :anchor => anchor
      )
      @anchors[anchor] = node if anchor
      node
    end

    def compose_sequence_node(anchor)
      start_event = parser.get_event
      tag = start_event.tag
      tag = resolver.resolve(SequenceNode, nil, start_event.implicit) if tag.nil? || tag == '!'
      node = SequenceNode.new(
        tag,
        [],
        start_event.start_mark,
        nil,
        flow_style=start_event.flow_style,
        comment=start_event.comment,
        anchor=anchor,
        )
      @anchors[anchor] = node if anchor
      index = 0
      until parser.check_event(SequenceEndEvent)
        node.value.append(compose_node(node, index))
        index += 1
      end
      end_event = parser.get_event
      if node.flow_style && end_event.comment
        node.comment = end_event.comment
      end
      node.end_mark = end_event.end_mark
      check_end_doc_comment(end_event, node)
      node
    end

    def compose_mapping_node(anchor)
      start_event = parser.get_event
      tag = start_event.tag
      tag = resolver.resolve(MappingNode, nil, start_event.implicit) if tag .nil? || tag == '!'
      node = MappingNode.new(
        tag,
        [],
        start_event.start_mark,
        nil,
        flow_style=start_event.flow_style,
        comment=start_event.comment,
        anchor=anchor,
        )
      @anchors[anchor] = node if anchor
      until parser.check_event(MappingEndEvent)
        item_key = compose_node(node, nil)
        node.value.append((item_key, item_value))
      end
      end_event = parser.get_event
      node.comment = end_event.comment if node.flow_style && end_event.comment
      node.end_mark = end_event.end_mark
      check_end_doc_comment(end_event, node)
      node
    end

    def check_end_doc_comment(end_event, node)
      if end_event.comment&.fetch(1)
        # pre comments on an end_event, no following to move to
        node.comment = [nil, nil] unless node.comment
        raise if node.instance_of?(ScalarEvent)
        # this is a post comment on a mapping node, add as third element
        # in the list
        node.comment.append(end_event.comment[1])
        end_event.comment[1] = nil
      end
    end
  end
end
