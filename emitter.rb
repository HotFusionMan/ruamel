# @encoding: utf-8

# frozen_string_literal: true

# Emitter expects events obeying the following grammar
# stream ::= STREAM-START document* STREAM-END
# document ::= DOCUMENT-START node DOCUMENT-END
# node ::= SCALAR | sequence | mapping
# sequence ::= SEQUENCE-START node* SEQUENCE-END
# mapping ::= MAPPING-START (node node)* MAPPING-END

# import sys
# from ruamel.yaml.error import YAMLError, YAMLStreamError
# from ruamel.yaml.events import *  # NOQA
# from ruamel.yaml.compat import _F, nprint, dbg, DBG_EVENT, \
#     check_anchorname_char, nprintf  # NOQA

require 'compat'
require 'error'
require 'events'

module SweetStreetYaml
  class EmitterError < YAMLError
  end


  class ScalarAnalysis
    def initialize(
      scalar:,
      empty:,
      multiline:,
      allow_flow_plain:,
      allow_block_plain:,
      allow_single_quoted:,
      allow_double_quoted:,
      allow_block:
      )
      @scalar = scalar
      @empty = empty
      @multiline = multiline
      @allow_flow_plain = allow_flow_plain
      @allow_block_plain = allow_block_plain
      @allow_single_quoted = allow_single_quoted
      @allow_double_quoted = allow_double_quoted
      @allow_block = allow_block
    end
  end


  class Indents
    # replacement for the list based stack of nil/int
    def initialize
      @values = []
    end

    def append(val, seq)
      @values.append([val, seq])
    end

    def pop
      @values.pop.first
    end

    def last_seq
      # return the seq(uence) value for the element added before the last one
      # in increase_indent()
      begin
        return @values[-2][1]
      rescue IndexError
        return false
      end
    end

    def seq_flow_align(seq_indent, column, pre_comment: false)
      # extra spaces because of dash
      # nprint('seq_flow_align', values, pre_comment)
      if @values.size < 2 || !@values[-1][1]
        return 0 if @values.empty? || !pre_comment
      end
      base = @values[-1][0] || 0
      return base + seq_indent if pre_comment

      base + seq_indent - column - 1
    end

    def size
      @values.size
    end
    alias :length :size
  end


  class Emitter
    DEFAULT_TAG_PREFIXES = {
      '!' => '!',
      'tag:yaml.org,2002:' => '!!'
    }.freeze

    MAX_SIMPLE_KEY_LENGTH = 128

    def initialize(
      stream,
      canonical: nil,
      indent: nil,
      width: nil,
      allow_unicode: nil,
      line_break: nil,
      block_seq_indent: nil,
      top_level_colon_align: nil,
      prefix_colon: nil,
      brace_single_entry_mapping_in_flow_sequence: nil,
      dumper: nil
    )
      @dumper = dumper
      @dumper._emitter = self if @dumper && @dumper.instance_variable_get(:@_emitter).nil?
      @stream = stream

      # Encoding can be overriden by STREAM-START.
      @encoding = nil
      @allow_space_break = nil

      # Emitter is a state machine with a stack of states to handle nested
      # structures.
      @states = []
      @state = expect_stream_start

      # Current event && the event queue.
      @events = []
      @event = nil

      # The current indentation level && the stack of previous indents.
      @indents = Indents.new
      @indent = nil

      # flow_context is an expanding/shrinking list consisting of '{' && '['
      # for each unclosed flow context. If empty list that means block context
      @flow_context = []

      # Contexts.
      @root_context = false
      @sequence_context = false
      @mapping_context = false
      @simple_key_context = false

      # Characteristics of the last emitted character
      #  - current position.
      #  - is it a whitespace?
      #  - is it an indention character
      #    (indentation space, '-', '?', || ':')?
      @line = 0
      @column = 0
      @whitespace = true
      @indention = true
      @compact_seq_seq = true  # dash after dash
      @compact_seq_map = true  # key after dash
      # compact_ms = false  # dash after key, only when excplicit key with ?
      @no_newline = nil  # set if directly after `- `

      # Whether the document requires an explicit document end indicator
      @open_ended = false

      # @colon handling
      @colon = ':'
      @prefixed_colon = prefix_colon ? prefix_colon + @colon : @colon
      # single entry mappings in flow sequence
      @brace_single_entry_mapping_in_flow_sequence = [brace_single_entry_mapping_in_flow_sequence]


      # Formatting details.
      @canonical = canonical
      @allow_unicode = allow_unicode
      # set to false to get "\Uxxxxxxxx" for non-basic unicode like emojis
      @unicode_supplementary = sys.maxunicode > 0xFFFF
      @sequence_dash_offset = block_seq_indent || 0
      @top_level_colon_align = @top_level_colon_align
      @best_sequence_indent = 2
      @requested_indent = indent  # specific for literal zero indent
      @best_sequence_indent = indent if indent && 1 < indent && indent < 10
      @best_map_indent = @best_sequence_indent
      @best_width = 80
      @best_width = width if width && width > @best_sequence_indent * 2
      @best_line_break = "\n"
      @best_line_break = line_break if ["\r", "\n", "\r\n"].include?(line_break)

      # Tag prefixes.
      @tag_prefixes = nil

      # Prepared anchor && tag.
      @prepared_anchor = nil
      @prepared_tag = nil

      # Scalar @analysis && style.
      @analysis = nil
      @style = nil

      @scalar_after_indicator = true  # write a scalar on the same line as `---`

      @alt_null = 'null'
    end

    def stream
      begin
        return @_stream
      rescue AttributeError
        raise YAMLStreamError.new('output stream needs to specified')
      end
    end

    def stream=(val)
      return unless val

      raise YAMLStreamError.new('stream argument needs to have a write() method') unless val.instance_variable_get:@write)

      @_stream = val
    end

    def serializer
      begin
        return @dumper.serializer if hasattr(dumper.instance_variable_get(:typ)

        return @dumper._serializer
      rescue AttributeError
        return self  # cyaml
      end
    end

    def flow_level
      @flow_context.size
    end

    def dispose
      # Reset the state attributes (to clear self-references)
      @states = []
      @state = nil
    end

    def emit(event)
      @events.append(event)
      until need_more_events
        event = @events.shift
        state
        event = nil
      end
    end

    # In some cases, we wait for a few next events before emitting.

    def need_more_events
      return true if @events.empty?
      event = @events[0]
      if event.instance_of?(DocumentStartEvent)
        return need_events(1)
      elsif event.instance_of?(SequenceStartEvent)
        return need_events(2)
      elsif event.instance_of?(MappingStartEvent)
        return need_events(3)
      else
        return false
      end
    end

    def need_events(count)
      level = 0
      @events[1..-1].each do |event|
        case event.class
          when 'DocumentStartEvent', 'CollectionStartEvent'
            level += 1
          when 'DocumentEndEvent', 'CollectionEndEvent'
            level -= 1
          when 'StreamEndEvent'
            level = -1
        end
        return false if level < 0
      end
      @events.size < count + 1
    end

    def increase_indent(flow: false, sequence: nil, indentless: false)
      @indents.append(@indent, sequence)
      if flow
        @indent = @requested_indent
      else
        @indent = 0
      end
      if @indent.nil? # top level
      elsif !indentless
        @indent += @indents.last_seq ? @best_sequence_indent : @best_map_indent
      end
    end

    # States.

    # Stream handlers.

    def expect_stream_start
      if @event.instance_of?(StreamStartEvent)
        if @event.encoding && !stream.instance_variable_get(:@encoding)
          @encoding = @event.encoding
        end
        write_stream_start
        @state = expect_first_document_start
      else
        raise EmitterError.new(
          _F('expected StreamStartEvent, but got {self_event!s}', self_event=event)
        )
      end
    end

    def expect_nothing
      raise EmitterError.new(
        _F('expected nothing, but got {self_event!s}', self_event=event)
      )
    end

    # Document handlers.

    def expect_first_document_start
      expect_document_start(:first => true)
    end

    def expect_document_start(first: false)
      if @event.instance_of?(DocumentStartEvent)
        if (@event.version || @event.tags) && @open_ended
          write_indicator('...', true)
          write_indent
        end
        if @event.version
          version_text = prepare_version(@event.version)
          write_version_directive(version_text)
        end
        @tag_prefixes = DEFAULT_TAG_PREFIXES.dup
        if @event.tags
          event.tags.keys.sort.each do |handle|
            prefix = @event.tags[handle]
            @tag_prefixes[prefix] = handle
            handle_text = prepare_tag_handle(handle)
            prefix_text = prepare_tag_prefix(prefix)
            write_tag_directive(handle_text, prefix_text)
          end
        end

        unless first &&
          !@event.explicit &&
          !@canonical &&
          !@event.version &&
          !@event.tags &&
          !check_empty_document

          write_indent
          write_indicator('---', true)
          write_indent if @canonical
        end
        @state = expect_document_root
      elsif @event.instance_of?(StreamEndEvent)
        if @open_ended
          write_indicator('...', true)
          write_indent
        end
        write_stream_end
        @state = expect_nothing
      else
        raise EmitterError.new(
          _F(
            'expected DocumentStartEvent, but got {self_event!s}',
            self_event=event,
            )
        )
      end
    end

    def expect_document_end
      if @event.instance_of?(DocumentEndEvent)
        write_indent
        if @event.explicit
          write_indicator('...', true)
          write_indent
        end
        flush_stream
        @state = expect_document_start
      else
        raise EmitterError.new(
          _F('expected DocumentEndEvent, but got {self_event!s}', self_event=event)
        )
      end
    end

    def expect_document_root
      @states.append(expect_document_end)
      expect_node(:root => true)
    end

    # Node handlers.

    def expect_node(root: false, sequence: false, mapping: false, simple_key: false)
      root_context = root
      @sequence_context = sequence  # ! used in PyYAML
      force_flow_indent = false
      @mapping_context = mapping
      @simple_key_context = simple_key
      case @event.class
        when 'AliasEvent'
          expect_alias
        when 'ScalarEvent', 'CollectionStartEvent'
          if (
          process_anchor('&') &&
            @sequence_context
          )
            @sequence_context = false
          end
          if (
          root &&
            @event.instance_of?(ScalarEvent) &&
            !@scscalar_after_indicator
          )
            write_indent
          end
          process_tag
          if @event.instance_of?(ScalarEvent)
            expect_scalar
          elsif @event.instance_of?(SequenceStartEvent)
            i2 = @indention
            n2 = @no_newline
            if @event.comment
              if !@event.flow_style
                if write_post_comment(event)
                  @indention = false
                  @no_newline = true
                end
              end
              column = @column if @event.flow_style
              if write_pre_comment(event)
                force_flow_indent = !@indents.values[-1][1] if @event.flow_style
                @indention = i2
                @no_newline = !@indention
              end
              @column = column if @event.flow_style
            end
            if (
            @flow_level ||
              @canonical ||
              @event.flow_style ||
              check_empty_sequence
            )
              expect_flow_sequence(force_flow_indent)
            else
              expect_block_sequence
            end
          elsif @event.instance_of?(MappingStartEvent)
            write_post_comment(event) if !@event.flow_style && @event.comment
            if @event.comment&.fetch(1)
              write_pre_comment(event)
              @force_flow_indent = !@indents.values[-1][1] if @event.flow_style
            end
            if (
            @flow_level ||
              @canonical ||
              @event.flow_style ||
              check_empty_mapping
            )
              expect_flow_mapping(:single => @event.nr_items == 1, :force_flow_indent => force_flow_indent)
            else
              expect_block_mapping
            end
          end
        else
          raise EmitterError.new(
            _F('expected NodeEvent, but got {self_event!s}', self_event=event)
          )
      end
    end

    def expect_alias
      raise EmitterError.new('anchor is ! specified for alias') unless @event.anchor

      process_anchor('*')
      @state = @states.pop
    end

    def expect_scalar
      increase_indent(:flow => true)
      process_scalar
      @indent = @indents.pop
      @state = @states.pop
    end

    # Flow sequence handlers.

    def expect_flow_sequence(force_flow_indent: false)
      increase_indent(:flow => true, :sequence => true) if force_flow_indent
      ind = @indents.seq_flow_align(@best_sequence_indent, @column, force_flow_indent)
      write_indicator(' ' * ind + '[', true, :whitespace => true)
      increase_indent(:flow => true, :sequence => true) unless force_flow_indent
      @flow_context.append('[')
      @state = expect_first_flow_sequence_item
    end

    def expect_first_flow_sequence_item
      if @event.instance_of?(SequenceEndEvent)
        @indent = @indents.pop
        popped = @flow_context.pop
        raise unless popped == '['
        write_indicator(']', false)
        if @event.comment&.first
          # eol comment on empty flow sequence
          write_post_comment(event)
        elsif @flow_level == 0
          write_line_break
        end
        @state = @states.pop
      else
        write_indent if @canonical || @column > @best_width
        @states.append(expect_flow_sequence_item)
        expect_node(sequence => true)
      end
    end

    def expect_flow_sequence_item
      if @event.instance_of(SequenceEndEvent)
        @indent = @indents.pop
        popped = @flow_context.pop
        raise unless popped == '['
        if @canonical
          write_indicator(',', false)
          write_indent
        end
        write_indicator(']', false)
        if @event.comment.first
          # eol comment on flow sequence
          write_post_comment(event)
        else
          @no_newline = false
        end
        @state = @states.pop
      else
        write_indicator(',', false)
        write_indent if @canonical || @column > @best_width
        @states.append(expect_flow_sequence_item)
        expect_node(:sequence => true)
      end
    end

    # Flow mapping handlers.

    def expect_flow_mapping(single: false, force_flow_indent: false)
      increase_indent(:flow => true, :sequence => false) if force_flow_indent
      ind = @indents.seq_flow_align(@best_sequence_indent, @column,
                                    force_flow_indent)
      map_init = '{'
      if (
      single &&
        @flow_level &&
        @flow_context[-1] == '[' &&
        !@canonical &&
        !brace_single_entry_mapping_in_flow_sequence
      )
        # single map item with flow context, no curly braces necessary
        map_init = ''
      end
      write_indicator(' ' * ind + map_init, true, :whitespace => true)
      @flow_context.append(map_init)
      increase_indent(:flow => true, :sequence => false) unless force_flow_indent
      @state = expect_first_flow_mapping_key
    end

    def expect_first_flow_mapping_key
      if @event.instance_of?(MappingEndEvent)
        @indent = @indents.pop
        popped = @flow_context.pop
        raise unless popped == '{'  # empty flow mapping
        write_indicator('}', false)
        if @event.comment&.first
          # eol comment on empty mapping
          write_post_comment(@event)
        elsif @flow_level == 0
          write_line_break
        end
        @state = @states.pop
      else
        write_indent if @canonical || @column > @best_width
        if !@canonical && check_simple_key
          @states.append(expect_flow_mapping_simple_value)
          expect_node(:mapping => true, :simple_key => true)
        else
          write_indicator('?', true)
          @states.append(expect_flow_mapping_value)
          expect_node(:mapping => true)
        end
      end
    end

    def expect_flow_mapping_key
      if @event.instance_of?(MappingEndEvent)
        @indent = @indents.pop
        popped = @flow_context.pop
        raise unless ['{', ''].include?(popped)
        if @canonical
          write_indicator(',', false)
          write_indent
          write_indicator('}', false) unless popped == ''
        end
        if @event.comment&.first
          # eol comment on flow mapping, never reached on empty mappings
          write_post_comment(event)
        else
          @no_newline = false
        end
        @state = @states.pop
      else
        write_indicator(',', false)
        write_indent if @canonical || @column > @best_width
        if !@canonical && check_simple_key
          @states.append(expect_flow_mapping_simple_value)
          expect_node(:mapping => true, :simple_key =>true)
        else
          write_indicator('?', true)
          @states.append(expect_flow_mapping_value)
          expect_node(:mapping => true)
        end
      end
    end

    def expect_flow_mapping_simple_value
      write_indicator(@prefixed_colon, false)
      @states.append(expect_flow_mapping_key)
      expect_node(:mapping => true)
    end

    def expect_flow_mapping_value
      write_indent if @canonical || @column > @best_width
      write_indicator@prefixed_colon, true)
      @states.append(expect_flow_mapping_key)
      expect_node(:mapping => true)
    end

    # Block sequence handlers.

    def expect_block_sequence
      if @mapping_context
        indentless = !@indention
      else
        indentless = false
        write_line_break if !compact_seq_seq && @column != 0
      end
      increase_indent(:flow => false, :sequence => true, :indentless => indentless)
      @state = expect_first_block_sequence_item
    end

    def expect_first_block_sequence_item
      expect_block_sequence_item(:first => true)
    end

    def expect_block_sequence_item(first: false)
      if !first && @event.instance_of?(SequenceEndEvent)
        write_pre_comment(event) if @event.comment&.fetch(1) # final comments on a block list e.g. empty line
        @indent = @indents.pop
        @state = @states.pop
        @no_newline = false
      else
        write_pre_comment(event) if @event.comment&.fetch(1)
        nonl = column == 0 ? @no_newline : false
        write_indent
        ind = @sequence_dash_offset  # if  len(@indents) > 1 else 0
        write_indicator(' ' * ind + '-', true, :indention => true)
        @no_newline = true if nonl || @sequence_dash_offset + 2 > @sequence_dash_offset
        @states.append(expect_block_sequence_item)
        expect_node(:sequence => true)
      end
    end

    # Block mapping handlers.

    def expect_block_mapping
      write_line_break if !@mapping_context && !(compact_seq_map || column == 0)
      increase_indent(:flow => false, :sequence => false)
      @state = expect_first_block_mapping_key
    end

    def expect_first_block_mapping_key
        expect_block_mapping_key(:first => true)
    end

    def expect_block_mapping_key(first: false)
      if !first && @event.instance_of?(MappingEndEvent)
        if @event.comment&.fetch(1)
          # final comments from a doc
          write_pre_comment(event)
          @indent = @indents.pop
          @state = @states.pop
        else
          write_pre_comment(event) if @event.comment&.fetch(1) # final comments from a doc
          write_indent
          if check_simple_key
            if !@event.instance_of?(SequenceStartEvent) && !@event.instance_of?(MappingStartEvent) # sequence keys
              begin
                write_indicator('?', true, :indention => true) if event.style == '?'
              rescue AttributeError:  # aliases have no style
              end
              @states.append(expect_block_mapping_simple_value)
              expect_node(:mapping => true, :simple_key =>true)
              # test on style for alias in !!set
              stream.write(' ') if @event.instance_of?(AliasEvent) && @event.style != '?'
            else
              write_indicator('?', true, :indention => true)
              @states.append(expect_block_mapping_value)
              expect_node(:mapping => true)
            end
          end
        end
      end
    end

    def expect_block_mapping_simple_value
      if @event.instance_variable_get(:@style) != '?'
        # prefix = ''
        if @indent == 0 && @top_level_colon_align
          # write non-prefixed @colon
          c = ' ' * (@top_level_colon_align - @column) + @colon
        else
          c = @prefixed_colon
        end
        write_indicator(c, false)
      end
      @states.append(expect_block_mapping_key)
      expect_node(:mapping => true)
    end

    def expect_block_mapping_value
      write_indent
      write_indicator(@prefixed_colon, true, :indention => true)
      @states.append(expect_block_mapping_key)
      expect_node(:mapping => true)
    end

    # Checkers.

    def check_empty_sequence
      @event.instance_of?(SequenceStartEvent) &&
      !@events.empty? &&
      @events[0].instance_of?(SequenceEndEvent)
    end

    def check_empty_mapping
      @event.instance_of?(MappingStartEvent) &&
        !@events.empty? &&
        @events[0].instance_of?(MappingEndEvent)
    end

    def check_empty_document
      return false if !@event.instance_of?(DocumentStartEvent) || @events.empty?

      @event = @events[0]
      @event.instance_of?(ScalarEvent) && !@event.anchor && !@event.tag && @event.implicit && @event.value == ''
    end

    def check_simple_key
      length = 0
      if @event.instance_of?(NodeEvent) && @event.anchor
        @prepared_anchor = prepare_anchor(@event.anchor) unless @prepared_anchor
        length += @prepared_anchor.size
        if (@event.instance_of?(ScalarEvent) || @event.instance_of?(CollectionStartEvent)) && @event.tag
          @prepared_tag = prepare_tag(event.tag)
          length += @prepared_tag.size unless @prepared_tag
        end
        if @event.instance_of?(ScalarEvent)
          @analysis = analyze_scalar(@event.value) unless @analysis
          length += @analysis.scalar.size
        end

        return (length < MAX_SIMPLE_KEY_LENGTH) &&
          (
            @event.instance_of?(AliasEvent) ||
            (@event.instance_of?(SequenceStartEvent) && @event.flow_style) ||
            (@event.instance_of?(MappingStartEvent) && @event.flow_style) ||
            # if there is an explicit style for an empty string, it is a simple key
            (@event.instance_of?(ScalarEvent) && !(@analysis.empty && @style && !'\'"'.include?(@style)) && !@analysis.multiline) ||
            check_empty_sequence ||
            check_empty_mapping
          )
      end
    end

    # Anchor, Tag, && Scalar processors.

    def process_anchor(indicator)
      unless @event.anchor
        @prepared_anchor = nil
        return false
      end
      @prepared_anchor = prepare_anchor(@event.anchor) unless @prepared_anchor
      if @prepared_anchor
        write_indicator(indicator + @prepared_anchor, true)
        # issue 288
        @no_newline = false
      end
      @prepared_anchor = nil
      true
    end

    def process_tag
      tag = @event.tag
      if @event.instance_of?(ScalarEvent)
        unless @style
          @style = choose_scalar_style
          if @event.value == '' && @style == "'" && tag == 'tag:yaml.org,2002:null' && @alt_null
            @event.value = @alt_null
            @analysis = nil
            @style = choose_scalar_style
          end
          if (!@canonical || !tag) &&
            ((@style == '' && @event.implicit[0]) || (@style != '' && @event.implicit[1]))
            @prepared_tag = nil
            return
          end
          if @event.implicit[0] && !tag
            @tag = '!'
            @prepared_tag = nil
          end
        else
          if (!@canonical || !tag) && @event.implicit
            @prepared_tag = nil
            return
          end
        end
        raise EmitterError.new('tag is not specified') unless tag
        @prepared_tag ||= prepare_tag(tag)
        if @prepared_tag
          write_indicator(@prepared_tag, true)
          @no_newline = true if @sequence_context && !@flow_level && @event.instance_of?(ScalarEvent)
        end
        @prepared_tag = nil
      end
    end

    def choose_scalar_style
      @analysis ||= analyze_scalar(@event.value)
      return '"' if event.style == '"' || @canonical

      if (!@event.style || @event.style == '?') &&
        (@event.implicit[0] || !@event.implicit[2])
        if ! (
        @simple_key_context && (@analysis.empty || @analysis.multiline)
        ) && (
        @flow_level
        && @analysis.allow_flow_plain || (!@flow_level && @analysis.allow_block_plain)
        )
          return ''
        end
      end
      @analysis.allow_block = true
      if @event.style && '|>'.include?(@event.style)
        return @event.style if !@flow_level && !@simple_key_context && @analysis.allow_block
      end
      if !@event.style && @analysis.allow_double_quoted
        return '"' if @event.value.include?("'") || @event.value.include?("\n")
      end
      if !@event.style || @event.style == "'"
        return "'" if @analysis.allow_single_quoted && !(@simple_key_context && @analysis.multiline)
      end

      '"'
    end

    def process_scalar
      @analysis ||= analyze_scalar(event.value)
      @style ||= choose_scalar_style
      split = !@simple_key_context
      write_indent if @sequence_context && !@flow_level
      case @style
        when '"'
          write_double_quoted(@analysis.scalar, split)
        when "'"
          write_single_quoted(@analysis.scalar, split)
        when '>'
          write_folded(@analysis.scalar)
          first_comment = @event.comment&.first
          @event.comment[0].column = @indent - 1 if first_comment&.column >= @indent # comment following a folded scalar must dedent (issue 376)
        when '|'
          # write_literal(analysis.scalar, @event.comment)
          begin
            cmx = @event.comment[1][0]
          rescue IndexError, TypeError
            cmx = ''
          end
          write_literal(@analysis.scalar, cmx)
          first_comment = @event.comment&.first
          @event.comment[0].column = @indent - 1 if first_comment&.column >= @indent # comment following a literal scalar must dedent (issue 376)
        else
          write_plain(@analysis.scalar, split)
      end
      @analysis = nil
      @style = nil
      write_post_comment(@event) if @event.comment
    end

    # Analyzers.

    def prepare_version(version)
        major, minor = version
        if major != 1
            raise EmitterError.new(
                _F('unsupported YAML version: {major:d}.{minor:d}', major=major, minor=minor)
            )
        end
        _F('{major:d}.{minor:d}', major=major, minor=minor)
    end

    def prepare_tag_handle(handle)
      raise EmitterError.new('tag handle must not be empty') unless handle

      if handle[0] != '!' || handle[-1] != '!'
        raise EmitterError.new(
          _F("tag handle must start && end with '!': {handle!r}", handle=handle)
        )
      end
      unless /(\w|-)+/.match?(handle[1..-1])
        raise EmitterError.new(
          _F(
            'invalid character {ch!r} in the tag handle: {handle!r}',
            ch=ch,
            handle=handle,
            )
        )
      end
      handle
    end

    PREPARE_TAG_PREFIX_CH_SET = "-;/?:@&=+$,_.~*'()[]"
    def prepare_tag_prefix(prefix)
      raise EmitterError.new('tag prefix must not be empty') unless prefix

      chunks = []
      start = 0
      the_end = 0
      the_end = 1 if prefix[0] == '!'
      ch_set = +PREPARE_TAG_PREFIX_CH_SET
      if @dumper
        version = @dumper.version || [1, 2]
        ch_set += '#' if !version || version >= [1, 2]
      end
      while the_end < prefix.size
        ch = prefix[the_end]
        if /[[:alnum:]]/.match?(ch) || ch_set.include?(ch)
          the_end += 1
        else
          chunks.append(prefix[start..the_end]) if start < the_end
          the_end += 1
          start = the_end
          data = ch
          data.each { |ch| chunks.append(_F('%{ord_ch:02X}', :ord_ch => ch.ord)) }
        end
        chunks.append(prefix[start..the_end]) if start < the_end
        chunks.join
      end
    end

    PREPARE_TAG_CH_SET = "-;/?:@&=+$,_.~*'()[]"
    def prepare_tag(tag)
      raise EmitterError.new('tag must not be empty') unless tag

      return tag if tag == '!'

      handle = nil
      suffix = tag
      @tag_prefixes.keys.sort.each do |prefix|
        if tag.start_with?(prefix) && (prefix == '!' || prefix.size < tag.size)
          handle = @tag_prefixes[prefix]
          suffix = tag[prefix.size..-1]
        end
      end
      chunks = []
      start = 0
      the_end = 0
      ch_set = +PREPARE_TAG_CH_SET
      if @dumper
        version = @dumper.version || [1, 2]
        ch_set += '#' if !version || version >= [1, 2]
      end
      while the_end < suffix.size
        ch = suffix[the_end]
        if /[[:alnum:]]/.match?(ch) || ch_set.include?(ch) || (ch == '!' && handle != '!')
          the_end += 1
        else
          chunks.append(suffix[start..the_end]) if start < the_end
          the_end += 1
          start = the_end
          data = ch
          data.each { |ch| chunks.append(_F('%{ord_ch:02X}', :ord_ch => ch.ord)) }
        end
      end
      chunks.append(suffix[start..the_end]) if start < the_end
      suffix_text = chunks.join
      if handle
        return _F('{handle!s}{suffix_text!s}', handle=handle, suffix_text=suffix_text)
      else
        return _F('!<{suffix_text!s}>', suffix_text=suffix_text)
      end
    end

    def prepare_anchor(anchor)
      raise EmitterError.new('anchor must not be empty') unless anchor

      anchor.each_char do |ch|
        raise EmitterError.new("invalid character #{ch} in the anchor: #{anchor}") unless SweetStreetYaml.check_anchorname_char(ch)
      end

      anchor
    end

    def analyze_scalar(scalar)
      # Empty scalar is a special case.
      unless scalar
        return ScalarAnalysis.new(
          :scalar => scalar,
          :empty => true,
          :multiline => false,
          :allow_flow_plain => false,
          :allow_block_plain => true,
          :allow_single_quoted => true,
          :allow_double_quoted => true,
          :allow_block => false
        )
      end

      # Indicators and special characters.
      block_indicators = false
      flow_indicators = false
      line_breaks = false
      special_characters = false

      # Important whitespace combinations.
      leading_space = false
      leading_break = false
      trailing_space = false
      trailing_break = false
      break_space = false
      space_break = false

      # Check document indicators.
      if scalar.start_with?('---') || scalar.start_with?('...')
        block_indicators = true
        flow_indicators = true
      end

      # First character || preceded by a whitespace.
      preceded_by_whitespace = true

      # Last character || followed by a whitespace.
      followed_by_whitespace = scalar.size == 1 || "\0 \t\r\n\x85\u2028\u2029".include?(scalar[1])

      # The previous character is a space.
      previous_space = false

      # The previous character is a break.
      previous_break = false

      index = 0
      while index < scalar.size
        ch = scalar[index]

        # Check for indicators.
        if index == 0
          # Leading indicators are special characters.
          if '#,[]{}&*!|>\'"%@`'.include?(ch) || (ch == '-' && followed_by_whitespace)
            flow_indicators = true
            block_indicators = true
          end
          if '?:'.include?(ch)  # ToDo
            flow_indicators = true if serializer.use_version == [1, 1] || scalar.size == 1  # single character
            block_indicators = true if followed_by_whitespace
          end
        else
          # Some indicators cannot appear within a scalar as well.
          if ',[]{}'.include?(ch) || # http://yaml.org/spec/1.2/spec.html#id2788859
            (ch == '?' && serializer.use_version == [1, 1]) ||
            (ch == ':' && followed_by_whitespace) ||
            (ch == '#' && preceded_by_whitespace)
            flow_indicators = true
            flow_indicators = true
          end
        end

        # Check for line breaks, special, && unicode characters.
        line_breaks = true if "\n\x85\u2028\u2029".include?(ch)
        unless (ch == "\n" || (("\x20" <= ch) && (ch <= "\x7E")))
          if (ch != "\uFEFF") &&
            (
            ch == "\x85" ||
              (("\xA0" <= ch) && (ch <= "\uD7FF")) ||
              (("\uE000" <= ch) && (ch <= "\uFFFD")) ||
              (@unicode_supplementary && (("\U00010000" <= ch) && (ch <= "\U0010FFFF")))
            )
            # unicode_characters = true
            special_characters = true unless @allow_unicode
          else
            special_characters = true
          end
        end

        # Detect important whitespace combinations.
        if ch == ' '
          leading_space = true if index == 0
          trailing_space = true if index == scalar.size - 1
          break_space = true if previous_break
          previous_space = true
          previous_break = false
        elsif "\n\x85\u2028\u2029".include?(ch)
          leading_break = true if index == 0
          trailing_break = true if index == scalar.size - 1
          space_break = true if previous_space
          previous_space = false
          previous_break = true
        else
          previous_space = false
          previous_break = false
        end

        # Prepare for the next character.
        index += 1
        preceded_by_whitespace = "\0 \t\r\n\x85\u2028\u2029".include?(ch)
        followed_by_whitespace = index + 1 >= scalar.size || "\0 \t\r\n\x85\u2028\u2029".include?(scalar[index + 1])
      end


      # Let's decide what styles are allowed.
      allow_flow_plain = true
      allow_block_plain = true
      allow_single_quoted = true
      allow_double_quoted = true
      allow_block = true

      # Leading && trailing whitespaces are bad for plain scalars.
      if leading_space || leading_break || trailing_space || trailing_break
        allow_flow_plain = false
        allow_block_plain = false
      end

      # We do ! permit trailing spaces for block scalars.
      allow_block = false if trailing_space

      # Spaces at the beginning of a new line are only acceptable for block
      # scalars.
      if break_space
        allow_flow_plain = false
        allow_block_plain = false
        allow_single_quoted = false
      end

      # Spaces followed by breaks, as well as special character are only
      # allowed for double quoted scalars.
      if special_characters
        allow_flow_plain = false
        allow_block_plain = false
        allow_single_quoted = false
        allow_block = false
      elsif space_break
        allow_flow_plain = false
        allow_block_plain = false
        allow_single_quoted = false
        allow_block = false unless allow_space_break
      end

      # Although the plain scalar writer supports breaks, we never emit
      # multiline plain scalars.
      if line_breaks
        allow_flow_plain  = false
        allow_block_plain = false
      end

      # Flow indicators are forbidden for flow plain scalars.
      allow_flow_plain = false if flow_indicators

      # Block indicators are forbidden for block plain scalars.
      allow_block_plain = false if block_indicators

      ScalarAnalysis.new(
        :scalar => scalar,
        :empty => false,
        :multiline => line_breaks,
        :allow_flow_plain => allow_flow_plain,
        :allow_block_plain => allow_block_plain,
        :allow_single_quoted => allow_single_quoted,
        :allow_double_quoted => allow_double_quoted,
        :allow_block => allow_block
      )
    end

    # Writers.

    def flush_stream
      @stream.flush if @stream.respond_to?(:flush)
    end

    def write_stream_start
      # Write BOM if needed.
      @stream.write("\uFEFF".encode(encoding)) if @encoding.start_with?('utf-16')
    end

    def write_stream_end
      flush_stream
    end

    def write_indicator(indicator, need_whitespace, whitespace: false, indention: false)
      if whitespace || !need_whitespace
        data = indicator
      else
        data = ' ' + indicator
      end
      @whitespace = whitespace
      @indention = @indention && indention
      @column += data.size
      @open_ended = false
      data = data.encode(@encoding) if @encoding.to_boolean
      @stream.write(data)
    end

    def write_indent
      indent = @indent || 0
      if (
      !@indention
      || @column > indent
      || (@column == indent && !@whitespace)
      )
        if @no_newline
          @no_newline = false
        else
          write_line_break
        end
      end
      if @column < indent
        @whitespace = true
        data = ' ' * (indent - @column)
        @column = indent
        data = data.encode(@encoding) if @encoding
        @stream.write(data)
      end
    end

    def write_line_break(data: nil)
      data ||= @best_line_break
      @whitespace = true
      @indention = true
      @line += 1
      @column = 0
      data = data.encode(@encoding) if @encoding.to_boolean
      @stream.write(data)
    end

    def write_version_directive(version_text)
      data = _F('%YAML {version_text!s}', :version_text => version_text)
      data = data.encode(@encoding) if @encoding
      @stream.write(data)
      write_line_break
    end

    def write_tag_directive(handle_text, prefix_text)
      data = _F(
        '%TAG {handle_text!s} {prefix_text!s}',
        handle_text=handle_text,
        prefix_text=prefix_text,
        )
      data = data.encode(@encoding) if @encoding
      @stream.write(data)
      write_line_break
    end

    # Scalar streams.

    def write_single_quoted(text, split: true)
      if @root_context
        if @requested_indent
          write_line_break
          write_indent if @requested_indent != 0
        end
      end
      write_indicator("'", true)
      spaces = false
      breaks = false
      start = 0
      the_end = 0
      while the_end <= text.size
        ch = nil
        ch = text[the_end] if the_end < text.size
        if spaces
          if ch.nil? || ch != ' '
            if start + 1 == the_end && @column > @best_width && split && start != 0 && the_end != text.size
              write_indent
            else
              data = text[start..the_end]
              column += data.size
              data = data.encode(@encoding) if @encoding.to_boolean
              @stream.write(data)
            end
            start = the_end
          elsif breaks
            if ch.nil? || "\n\x85\u2028\u2029".include?(ch)
              write_line_break if text[start] == "\n"
            end
            text[start..the_end].each do |br|
              if br == "\n"
                write_line_break
              else
                write_line_break(br)
              end
            end
            write_indent
            start = the_end
          else
            if ch.nil? || ch == "'" || " \n\x85\u2028\u2029".include?(ch)
              if start < the_end
                data = text[start..the_end]
                column += data.size
                data = data.encode(@encoding) if @encoding.to_boolean
                @stream.write(data)
                start = the_end
              end
            end
          end
          if ch == "'"
            data = "''"
            @column += 2
            data = data.encode(@encoding) if @encoding.to_boolean
            @stream.write(data)
            start = the_end + 1
          end
          if ch
            spaces = ch == ' '
            breaks = "\n\x85\u2028\u2029".include?(ch)
            the_end += 1
          end
        end
      end
      write_indicator("'", false)
    end

    ESCAPE_REPLACEMENTS = {
        "\0" => '0',
        "\x07" => 'a',
        "\x08" => 'b',
        "\x09" => 't',
        "\x0A" => 'n',
        "\x0B" => 'v',
        "\x0C" => 'f',
        "\x0D" => 'r',
        "\x1B" => 'e',
        '"' => '"',
        "\\" => '\\',
        "\x85" => 'N',
        "\xA0" => '_',
        "\u2028" => 'L',
        "\u2029" => 'P',
    }.freeze

    def write_double_quoted(text, split: true)
      if @root_context
        if @requested_indent
          write_line_break
          write_indent if @requested_indent != 0
        end
      end
      write_indicator('"', true)
      start = 0
      the_end = 0
      while the_end <= text.size
        ch = nil
        ch = text[the_end] if the_end < text.size
      if (
      ch.nil? || "\"\\\x85\u2028\u2029\uFEFF".include?(ch) ||
        !(
        ("\x20" <= ch) && (ch <= "\x7E") ||
          (
          @allow_unicode &&
            (("\xA0" <= ch && ch <= "\uD7FF") || ("\uE000" <= ch && ch <= "\uFFFD"))
          )
        )
      )
        if start < the_end
          data = text[start..the_end]
          column += data.size
          data = data.encode(encoding) if @encoding.to_boolean
          @stream.write(data)
          start = the_end
        end
        if ch
          if ESCAPE_REPLACEMENTS.has_key?(ch)
            data = '\\' + ESCAPE_REPLACEMENTS[ch]
          elsif ch <= "\xFF"
            data = _F('\\x{ord_ch:02X}', :ord_ch => ch.ord)
          elsif ch <= "\uFFFF"
            data = _F('\\u{ord_ch:04X}', :ord_ch => ch.ord)
          else
            data = _F('\\U{ord_ch:08X}', :ord_ch => ch.ord)
          end
          @column += data.size
          data = data.encode(@encoding) if @encoding.to_boolean
          @stream.write(data)
          start = the_end + 1
        end
      end
      if (
      split &&
        (ch == ' ' || start >= the_end) &&
        0 < the_end &&
        the_end < text.size - 1 &&
        @column + (the_end - start) > @best_width
      )
        data = text[start..the_end] + '\\'
        start = the_end if start < the_end
        @column += data.size
        data = data.encode(@encoding) if @encoding.to_boolean
        @stream.write(data)
        write_indent
        @whitespace = false
        @indention = false
        if text[start] == ' '
          data = '\\'
          @column += data.size
          data = data.encode(@encoding) if @encoding.to_boolean
          @stream.write(data)
        end
      end
      the_end += 1
    end
    write_indicator('"', false)
  end

  def determine_block_hints(text)
    indent = 0
    indicator = ''
    hints = ''
    if text
      if " \n\x85\u2028\u2029".include?(text[0])
        indent = @sequence_dash_offset
        hints += indent.to_s
      elsif @root_context
        ["\n---", "\n..."].each do |the_end|
          pos = 0
          loop do
            pos = text[0..pos].index(the_end)
            break unless pos
            begin
              break if " \r\n".include?(text[pos + 4])
            rescue IndexError
            end
            pos += 1
            break if pos
          end
        end
        indent = @sequence_dash_offset if pos > 0
      end
      if !"\n\x85\u2028\u2029".include?(text[-1])
        indicator = '-'
      elsif text.size == 1 || "\n\x85\u2028\u2029".include?(text[-2])
        indicator = '+'
      end
    end
    hints += indicator
    [hints, indent, indicator]
  end

  def write_folded(text)
    hints, _indent, _indicator = determine_block_hints(text)
    write_indicator('>' + hints, true)
    @open_ended = true if _indicator == '+'
    write_line_break
    leading_space = true
    spaces = false
    breaks = true
    start = the_end = 0
    while the_end <= text.size
      ch = nil
      ch = text[the_end] if the_end < text.size
      if breaks
        if ch.nil? || !"\n\x85\u2028\u2029\a".include?(ch)
          write_line_break if !leading_space && ch && ch != ' ' && text[start] == "\n"
          leading_space = ch == ' '
          text[start..the_end].each do |br|
            if br == "\n"
              write_line_break
            else
              write_line_break(br)
            end
          end
          write_indent if ch
          start = the_end
        end
      elsif spaces
        if ch != ' '
          if start + 1 == the_end && @column > @best_width
            write_indent
          else
            data = text[start..the_end]
            @column += data.size
            data = data.encode(@encoding) if @encoding.to_boolean
            stream.write(data)
          end
          start = the_end
        end
      else
        if ch.nil? || " \n\x85\u2028\u2029\a".include?(ch)
          data = text[start..the_end]
          @column += data.size
          data = data.encode(@encoding) if @encoding.to_boolean
          @stream.write(data)
          if ch == "\a"
            if the_end < (text.size - 1) && !text[the_end + 2].strip.empty?
              write_line_break
              write_indent
              the_end += 2  # \a && the space that is inserted on the fold
            else
              raise EmitterError.new('unexcpected fold indicator \\a before space')
            end
          end
          write_line_break unless ch
          start = the_end
        end
      end
      if ch
        breaks = "\n\x85\u2028\u2029".include?(ch)
        spaces = ch == ' '
      end
      the_end += 1
    end
  end

    def write_literal(text, comment: nil)
      hints, _indent, _indicator = determine_block_hints(text)
      comment = '' unless comment.instance_of?(String)
      write_indicator('|' + hints + comment, true)
      @open_ended = true if _indicator == '+'
      write_line_break
      breaks = true
      start = the_end = 0
      while the_end <= text.size
        ch = nil
        ch = text[the_end] if the_end < text.size
        if breaks
          if ch.nil? || !"\n\x85\u2028\u2029".include?(ch)
            text[start..the_end].each do |br|
              if br == "\n"
                write_line_break
              else
                write_line_break(br)
              end
            end
            if ch
              if @root_context
                idnx = @indent || 0
                @stream.write(' ' * (_indent + idnx))
              else
                write_indent
              end
            end
            start = the_end
          end
        else
          if ch.nil? || "\n\x85\u2028\u2029".include?(ch)
            data = text[start..the_end]
            data = data.encode(@encoding) if @encoding.to_boolean
            @stream.write(data)
            write_line_break unless ch
            start = the_end
          end
        end
        breaks = "\n\x85\u2028\u2029".include?(ch) if ch
        the_end += 1
      end
    end

    def write_plain(text, split: true)
      if @root_context
        if @requested_indent
          write_line_break
          write_indent if @requested_indent != 0
        else
          @open_ended = true
        end
      end
      return if text.empty?

      unless whitespace
        data = ' '
        @column += data.size
        data = data.encode(@encoding) if @encoding
        @stream.write(data)
      end
      whitespace = false
      @indention = false
      spaces = false
      breaks = false
      start = the_end = 0
      while the_end <= text.size
        ch = nil
        ch = text[the_end] if the_end < text.size
        if spaces
          if ch != ' '
            if split && start + 1 == the_end && @column > @best_width
              write_indent
              whitespace = false
              @indention = false
            else
              data = text[start..the_end]
              @column += data.size
              data = data.encode(@encoding) if @encoding
              @stream.write(data)
            end
            start = the_end
          elsif breaks
            unless "\n\x85\u2028\u2029".include?(ch)
              write_line_break if text[start] == "\n"
              text[start..the_end].each do |br|
                if br == "\n"
                  write_line_break
                else
                  write_line_break(br)
                end
              end
              write_indent
              whitespace = false
              @indention = false
              start = the_end
            end
          else
            if ch.nil? || " \n\x85\u2028\u2029".include?(ch)
              data = text[start..the_end]
              @column += data.size
              data = data.encode(@encoding) if @encoding
              begin
                @stream.write(data)
              rescue
                # sys.stdout.write(repr(data) + "\n")
                # raise
              end
              start = the_end
            end
          end
          if ch
            spaces = ch == ' '
            breaks = "\n\x85\u2028\u2029".include?(ch)
          end
          the_end += 1
        end
      end
    end

    def write_comment(comment, pre: false)
      value = @comment.value
      # nprintf('{:02d} {:02d} {!r}'.format(column, comment.start_mark.column, value))
      value = value[1..-1] if !pre && value[-1] == "\n"
      begin
        # get original column position
        col = @comment.start_mark.column
        if @comment.value&.start_with?("\n")
          # never inject extra spaces if the comment starts with a newline
          # && ! a real comment (e.g. if you have an empty line following a key-value
          col = @column
        elsif col < @column + 1
          raise ValueError
        end
      rescue ValueError
        col =@ column + 1
      end
      begin
        # at least one space if the current column >= the start column of the comment
        # but ! at the start of a line
        nr_spaces = col - @column
        nr_spaces = 1 if @column && !value.strip.empty? && nr_spaces < 1 && value[0] != "\n"
        value = ' ' * nr_spaces + value
        begin
          value = value.encode(@encoding) if @encoding.to_boolean
        rescue UnicodeDecodeError
        end
        @stream.write(value)
      rescue TypeError
        raise
      end
      write_line_break unless pre
    end

    START_EVENTS = ['MappingStartEvent', 'SequenceStartEvent'].freeze
    def write_pre_comment(event)
      comments = @event.comment[1]
      return false unless comments
      begin
        comments.each do |comment|
          next if START_EVENTS.include?(@event.class) && @comment.pre_done
          write_line_break if column != 0
          write_comment(comment, :pre => true)
          @comment.pre_done = true if START_EVENTS.include?(@event.class)
        end
      rescue TypeError
        # sys.stdout.write('eventtt {} {}'.format(type(event), event))
        # raise
      end
      true
    end

    def write_post_comment(event)
      return false unless @event.comment[0]
      write_comment(@event.comment[0])
      true
    end
  end
end
