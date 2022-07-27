# frozen_string_literal: true

# Scanner produces tokens of the following types:
# STREAM-START
# STREAM-END
# DIRECTIVE(name, value)
# DOCUMENT-START
# DOCUMENT-END
# BLOCK-SEQUENCE-START
# BLOCK-MAPPING-START
# BLOCK-END
# FLOW-SEQUENCE-START
# FLOW-MAPPING-START
# FLOW-SEQUENCE-END
# FLOW-MAPPING-END
# BLOCK-ENTRY
# FLOW-ENTRY
# KEY
# VALUE
# ALIAS(value)
# ANCHOR(value)
# TAG(value)
# SCALAR(value, plain, style)
#
# RoundTripScanner
# COMMENT(value)
#
# Read comments in the Scanner code for more details.

require 'error'
require 'tokens'
require 'compat'
require 'numeric_extensions'

module Ruamel
  using NumericExtensions

  class Scanner
    _THE_END = "\n\0\r\x85\u2028\u2029"
    _THE_END_SPACE_TAB = " \n\0\t\r\x85\u2028\u2029"
    _SPACE_TAB = " \t"


    def initialize(loader = nil)
      # It is assumed that Scanner and Reader will have a common descendant.
      # Reader do the dirty work of checking for BOM and converting the
      # input data to Unicode. It also adds NUL to the end.
      #
      # Reader supports the following methods
      #   self.peek(i=0)    # peek the next i-th character
      #   self.prefix(l=1)  # peek the next l characters
      #   self.forward(l=1) # read the next l characters and move the pointer

      @loader = loader
      if @loader && !@loader.respond_to?(:_scanner)
        @loader._scanner = self
      end
      reset_scanner
      @first_time = false
      @yaml_version = nil
    end

    def flow_level
      @flow_context.size
    end

    def reset_scanner
      # Had we reached the end of the stream?
      @done = false

      # flow_context is an expanding/shrinking list consisting of '{' and '['
      # for each unclosed flow context. If empty list that means block context
      @flow_context = []  # type: List[Text]

      # List of processed tokens that are not yet emitted.
      @tokens = []

      # Add the STREAM-START token.
      fetch_stream_start

      # Number of tokens that were emitted through the `get_token` method.
      @tokens_taken = 0

      # The current indentation level.
      @indent = -1

      # Past indentation levels.
      @indents = []  # type: List[int]

      # Variables related to simple keys treatment.

      # A simple key is a key that is not denoted by the '?' indicator.
      # Example of simple keys:
      #   ---
      #   block simple key: value
      #   ? not a simple key:
      #   : { flow simple key: value }
      # We emit the KEY token before all keys, so when we find a potential
      # simple key, we try to locate the corresponding ':' indicator.
      # Simple keys should be limited to a single line and 1024 characters.

      # Can a simple key start at the current position? A simple key may
      # start:
      # - at the beginning of the line, not counting indentation spaces
      #       (in block context),
      # - after '{', '[', ',' (in the flow context),
      # - after '?', ':', '-' (in the block context).
      # In the block context, this flag also signifies if a block collection
      # may start at the current position.
      @allow_simple_key = true

      # Keep track of possible simple keys. This is a dictionary. The key
      # is `flow_level`; there can be no more that one possible simple key
      # for each level. The value is a SimpleKey record:
      #   (token_number, required, index, line, column, mark)
      # A simple key may start with ALIAS, ANCHOR, TAG, SCALAR(flow),
      # '[', or '{' tokens.
      @possible_simple_keys = {}  # type: Dict[Any, Any]
    end

    def reader
      return(@_scanner_reader) if defined?(@_scanner_reader)
    # rescue AttributeError
      if @loader.respond_to?(:typ)
        @_scanner_reader = @loader.reader
      else
        @_scanner_reader = @loader._reader
      end
    end

    def scanner_processing_version  # prefix until un-composited
      return(@scanner_processing_version) if defined?(@scanner_processing_version)

      @scanner_processing_version =
        if @loader.respond_to?(:typ)
          @loader.resolver.processing_version
        else
          @loader.processing_version
        end
    end

    # public

    def check_token(*choices)
      # Check if the next token is one of the given types.
      while need_more_tokens
        fetch_more_tokens
      end
      if @tokens.size > 0
        return true if choices.empty?
        first_token = @tokens[0]
        choices.each { |choice| return true if first_token.instance_of?(choice) }
      end
      false
    end

    def peek_token
      # Return the next token, but do not delete it from the queue.
      while need_more_tokens
        fetch_more_tokens
      end
      return(@tokens[0]) if @tokens.size > 0
    end

    def get_token
      # Return the next token.
      while need_more_tokens
        fetch_more_tokens
      end
      if @tokens.size > 0
        @tokens_taken += 1
        return @tokens.pop(0)
      end
    end

    # private

    def need_more_tokens
      return false if @done
      return true if @tokens.empty?
      # The current token may be a potential simple key, so we need to look further.
      stale_possible_simple_keys
      return true if next_possible_simple_key == @tokens_taken
      false
    end

    def fetch_comment(_comment)
      raise NotImplementedError
    end

    def fetch_more_tokens
      # Eat whitespaces and comments until we reach the next token.
      comment = scan_to_next_token
      return fetch_comment(comment) if comment # never happens for base scanner
      # Remove obsolete possible simple keys.
      stale_possible_simple_keys

      # Compare the current indentation and column. It may add some tokens
      # and decrease the current indentation level.
      unwind_indent(reader.column)

      # Peek the next character.
      ch = reader.peek

      # Is it the end of stream?
      return fetch_stream_end if ch == "\0"

      # Is it a directive?
      return fetch_directive if ch == '%' && check_directive

      # Is it the document start?
      return fetch_document_start if ch == '-' && check_document_start

      # Is it the document end?
      return fetch_document_end if ch == '.' && check_document_end

      # TODO: support for BOM within a stream.
      # return fetch_bom if ch == "\uFEFF" # <-- issue BOMToken

      # Note: the order of the following checks is NOT significant.

      # Is it the flow sequence start indicator?
      return fetch_flow_sequence_start if ch == '['

      # Is it the flow mapping start indicator?
      return fetch_flow_mapping_start if ch == '{'

      # Is it the flow sequence end indicator?
      return fetch_flow_sequence_end if ch == ']'

      # Is it the flow mapping end indicator?
      return fetch_flow_mapping_end if ch == '}'

      # Is it the flow entry indicator?
      return fetch_flow_entry if ch == ','

      # Is it the block entry indicator?
      return fetch_block_entry if ch == '-' && check_block_entry

      # Is it the key indicator?
      return fetch_key if ch == '?' && check_key

      # Is it the value indicator?
      return fetch_value if ch == '' && check_value

      # Is it an alias?
      return fetch_alias if ch == '*'

      # Is it an anchor?
      return fetch_anchor if ch == '&'

      # Is it a tag?
      return fetch_tag if ch == '!'

      # Is it a literal scalar?
      return fetch_literal if (ch == '|') && !flow_level

      # Is it a folded scalar?
      return fetch_folded if (ch == '>') && !flow_level

      # Is it a single-quoted scalar?
      return fetch_single if ch == "'"

      # Is it a double-quoted scalar?
      return fetch_double if ch == '"'

      # It must be a plain scalar then.
      return fetch_plain if check_plain

      # No? It's an error. Let's produce a nice error message.
      raise ScannerError.new(
        'while scanning for the next token',
        nil,
        _F('found character {ch!r} that cannot start any token', ch=ch),
        reader.get_mark
      )
    end

    # Simple keys treatment.

    def next_possible_simple_key
      # Return the number of the nearest possible simple key. Actually we
      # don't need to loop through the whole dictionary. We may replace it
      # with the following code:
      #   return nil unless possible_simple_keys
      #   return possible_simple_keys[possible_simple_keys.keys.min].token_number
      min_token_number = nil
      possible_simple_keys.each do |level|
        key = possible_simple_keys[level]
        if min_token_number.nil? || (key.token_number < min_token_number)
          min_token_number = key.token_number
        end
      end
      min_token_number
    end

    def stale_possible_simple_keys
      # Remove entries that are no longer possible simple keys. According to
      # the YAML specification, simple keys
      # - should be limited to a single line,
      # - should be no longer than 1024 characters.
      # Disabling this procedure will allow simple keys of any length and
      # height (may cause problems if indentation is broken though).
      @possible_simple_keys.keys do |level|
        key = @possible_simple_keys[level]
        if (key.line != reader.line) || (reader.index - key.index > 1024)
          if key.required
            raise ScannerError.new(
              'while scanning a simple key',
              key.mark,
              "could not find expected ':'",
              reader.get_mark
            )
          end
          @possible_simple_keys[level] = nil
        end
      end
    end

    def save_possible_simple_key
      # The next token may start a simple key. We check if it's possible
      # and save its position. This function is called for
      #   ALIAS, ANCHOR, TAG, SCALAR(flow), '[', and '{'.

      # Check if a simple key is required at the current position.
      required = not self.flow_level and self.indent == self.reader.column

      # The next token might be a simple key. Let's save it's number and
      # position.
      if allow_simple_key
        remove_possible_simple_key
        token_number = @tokens_taken + @tokens.size
        key = SimpleKey.new(
          token_number,
          required,
          reader.index,
          reader.line,
          reader.column,
          reader.get_mark
        )
        @possible_simple_keys[flow_level] = key
      end
    end

    def remove_possible_simple_key
      # Remove the saved possible key position at the current flow level.
      if @possible_simple_keys.has_key?(flow_level)
        key = self.possible_simple_keys[self.flow_level]

        if key.required
          raise ScannerError.new(
            'while scanning a simple key',
            key.mark,
            "could not find expected ':'",
            reader.get_mark
          )
        end

        @possible_simple_keys[flow_level] = nil
      end
    end

    # Indentation functions.

    def unwind_indent(column)
      # In flow context, tokens should respect indentation.
      # Actually the condition should be `self.indent >= column` according to
      # the spec. But this condition will prohibit intuitively correct
      # constructions such as
      # key : {
      # }
      # ####
      # if self.flow_level and self.indent > column:
      #     raise ScannerError(None, None,
      #             "invalid intendation or unclosed '[' or '{'",
      #             self.reader.get_mark())

      # In the flow context, indentation is ignored. We make the scanner less
      # restrictive then specification requires.
      if (flow_level == 0) ? false : true
        return
      end

      # In block context, we may need to issue the BLOCK-END tokens.
      while @indent > column
        mark = reader.get_mark
        @indent = @indents.pop
        @tokens.append(BlockEndToken.new(mark, mark))
      end
    end

    def add_indent(column)
      # Check if we need to increase indentation.
      if @indent < column
        @indents.append(@indent)
        @indent = column
        return true
      end
      false
    end

    # Fetchers.

    def fetch_stream_start
      # We always add STREAM-START as the first token and STREAM-END as the
      # last token.
      # Read the token.
      mark = reader.get_mark
      # Add STREAM-START.
      @tokens.append(StreamStartToken.new(mark, mark, encoding=reader.encoding))
    end

    def fetch_stream_end
      # Set the current intendation to -1.
      unwind_indent(-1)
      # Reset simple keys.
      remove_possible_simple_key
      @allow_simple_key = false
      @possible_simple_keys = {}
      # Read the token.
      mark = reader.get_mark
      # Add STREAM-END.
      @tokens.append(StreamEndToken.new(mark, mark))
      # The stream is finished.
      @done = true
    end

    def fetch_directive
      # Set the current intendation to -1.
      unwind_indent(-1)

      # Reset simple keys.
      remove_possible_simple_key
      @allow_simple_key = false

      # Scan and add DIRECTIVE.
      tokens.append(scan_directive)
    end

    def fetch_document_start
      fetch_document_indicator(DocumentStartToken)
    end

    def fetch_document_end
      fetch_document_indicator(DocumentEndToken)
    end

    def fetch_document_indicator(token_class)
      # Set the current intendation to -1.
      unwind_indent(-1)

      # Reset simple keys. Note that there could not be a block collection
      # after '---'.
      remove_possible_simple_key
      @allow_simple_key = false

      # Add DOCUMENT-START or DOCUMENT-END.
      start_mark = reader.get_mark
      reader.forward(3)
      end_mark = reader.get_mark
      @tokens.append(token_class.new(start_mark, end_mark))
    end

    def fetch_flow_sequence_start
      fetch_flow_collection_start(FlowSequenceStartToken, '[')
    end

    def fetch_flow_mapping_start
      fetch_flow_collection_start(FlowMappingStartToken, '{')
    end

    def fetch_flow_collection_start(token_class, to_push)
      # '[' and '{' may start a simple key.
      save_possible_simple_key
      # Increase the flow level.
      flow_context.append(to_push)
      # Simple keys are allowed after '[' and '{'.
      @allow_simple_key = true
      # Add FLOW-SEQUENCE-START or FLOW-MAPPING-START.
      start_mark = reader.get_mark
      reader.forward
      end_mark = reader.get_mark
      @tokens.append(token_class.new(start_mark, end_mark))
    end

    def fetch_flow_sequence_end
      fetch_flow_collection_end(FlowSequenceEndToken)
    end

    def fetch_flow_mapping_end
      fetch_flow_collection_end(FlowMappingEndToken)
    end

    def fetch_flow_collection_end(token_class)
      # Reset possible simple key on the current level.
      remove_possible_simple_key
      # Decrease the flow level.
      begin
        popped = @flow_context.pop
      rescue IndexError
        # We must not be in a list or object.
        # Defer error handling to the parser.
      end
      # No simple keys after ']' or '}'.
      @allow_simple_key = false
      # Add FLOW-SEQUENCE-END or FLOW-MAPPING-END.
      start_mark = reader.get_mark
      reader.forward
      end_mark = reader.get_mark
      @tokens.append(token_class.new(start_mark, end_mark))
    end

    def fetch_flow_entry
      # Simple keys are allowed after ','.
      @allow_simple_key = true
      # Reset possible simple key on the current level.
      remove_possible_simple_key
      # Add FLOW-ENTRY.
      start_mark = reader.get_mark
      reader.forward
      end_mark = reader.get_mark
      @tokens.append(FlowEntryToken.new(start_mark, end_mark))
    end

    def fetch_block_entry
      # Block context needs additional checks.
      unless flow_level.to_boolean
        # Are we allowed to start a new entry?
        unless @allow_simple_key
          raise ScannerError.new(nil, nil, 'sequence entries are not allowed here', reader.get_mark)
        end
        # We may need to add BLOCK-SEQUENCE-START.
        if add_indent(reader.column)
          mark = reader.get_mark
          @tokens.append(BlockSequenceStartToken.new(mark, mark))
        end
        # It's an error for the block entry to occur in the flow context,
        # but we let the parser detect this.
      end
      # Simple keys are allowed after '-'.
      @allow_simple_key = true
      # Reset possible simple key on the current level.
      remove_possible_simple_key

      # Add BLOCK-ENTRY.
      start_mark = reader.get_mark
      reader.forward
      end_mark = self.reader.get_mark
      @tokens.append(BlockEntryToken.new(start_mark, end_mark))
    end

    d
  end
end
