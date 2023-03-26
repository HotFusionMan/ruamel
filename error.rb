# encoding: utf-8

# import warnings
# import textwrap

# from ruamel.yaml.compat import _F

module SweetStreetYaml
  class StreamMark
    attr_accessor :name, :index, :line, :column

    def initialize(name, index, line, column)
      @name = name
      @index = index
      @line = line
      @column = column
    end

    def to_str
      "  in '#{name}', line #{line + 1}, column #{column + 1}"
    end

    def eql?(other)
      return false if @line != other.line || @column != other.column || @name != other.name || @index != other.index

      true
    end

    # def __ne__(self, other)
    #     # type: (Any) -> bool
    #     return  !__eq__(other)
  end

  class FileMark < StreamMark
  end


  class StringMark < StreamMark
    attr_accessor :name, :index, :line, :column, :buffer, :pointer

    def initialize(name, index, line, column, buffer, pointer)
      super(name, index, line, column)
      @buffer = buffer
      @pointer = pointer
    end

    def get_snippet(indent: 4, max_length: 75)
        return nil unless @buffer  # always false
        head = ''
        start = @pointer
        while start > 0 && !"\0\r\n\u{9b}\u2028\u2029".include?(@buffer[start - 1] )
            start -= 1
            if @pointer - start > max_length / 2 - 1
                head = ' ... '
                start += 5
                break 
            end
        end
        tail = ''
        the_end = @pointer
        while the_end < @buffer.size && !"\0\r\n\u{9b}\u2028\u2029".include?(@buffer[the_end])
            the_end += 1
            if the_end - @pointer > max_length / 2 - 1
                tail = ' ... '
                the_end -= 5
                break 
            end
        end
        snippet = @buffer[start..the_end]
        caret = "^ (line: #{@line + 1})"
        return (
            ' ' * indent
            + head
            + snippet
            + tail
            + "\n"
            + ' ' * (indent + @pointer - start + head.size)
            + caret
        )
    end

    def to_str
      snippet = get_snippet
      where = _F(
        '  in "{sname!s}", line {sline1:d}, column {scolumn1:d}',
        sname=name,
        sline1=line + 1,
        scolumn1=column + 1,
        )
      where += ":\n" + snippet if snippet
      where
    end

    def to_s
      snippet = get_snippet
      where = "  in "#{name}", line #{line + 1}, column #{column + 1}",
      where += ":\n" + snippet if snippet
      where
    end
  end


  class CommentMark
    attr_accessor :column

    def initialize(column)
      @column = column
    end
  end


  class YAMLError < Exception
  end


  class MarkedYAMLError < YAMLError
    def initialize(
        context: nil,
        context_mark: nil,
        problem: nil,
        problem_mark: nil,
        note: nil,
        warn: nil
    )
        @context = context
        @context_mark = context_mark
        @problem = problem
        @problem_mark = problem_mark
        @note = note
        # warn is ignored
    end

    def to_str
      lines = []
      lines.append(@context) if @context
      if @context_mark && (
        @problem.nil? ||
        @problem_mark.nil? ||
        @context_mark.name != @problem_mark.name ||
        @context_mark.line != @problem_mark.line ||
        @context_mark.column != @problem_mark.column
      )
        lines.append(@context_mark.to_s)
      end
      lines.append(@problem) if @problem
      lines.append(@problem_mark.to_s) if @problem_mark
      if @note
        note = textwrap.dedent(@note)
        lines.append(note)
      end
      lines.join("\n")
    end
  end


  class YAMLStreamError < Exception
  end


  class YAMLWarning < Exception
  end


  class MarkedYAMLWarning < YAMLWarning
    def initialize(
        context: nil,
        context_mark: nil,
        problem: nil,
        problem_mark: nil,
        note: nil,
        warn: nil
    )
        @context = context
        @context_mark = context_mark
        @problem = problem
        @problem_mark = problem_mark
        @note = note
        @warn = warn
    end

    def to_str
      lines = []
      lines.append(@context) if @context
      if @context_mark && (
        @problem.nil? ||
        @problem_mark .nil? ||
        @context_mark.name != @problem_mark.name ||
        @context_mark.line != @problem_mark.line ||
        @context_mark.column != @problem_mark.column
      )
        lines.append(@context_mark.to_s)
      end
      lines.append(@problem) if @problem
      lines.append(@problem_mark.to_s) if @problem_mark
      if @note
        note = textwrap.dedent(@note)
        lines.append(note)
      end
      if @warn
        warn = textwrap.dedent(@warn)
        lines.append(warn)
      end
      lines.join("\n")
    end
  end


  class ReusedAnchorWarning < YAMLWarning
  end


  class UnsafeLoaderWarning < YAMLWarning
    text = "
The default 'Loader' for 'load(stream)' without further arguments can be unsafe.
Use 'load(stream, Loader=ruamel.yaml.Loader)' explicitly if that is OK.
Alternatively include the following in your code

  import warnings
  warnings.simplefilter('ignore', ruamel.yaml.error.UnsafeLoaderWarning)

In most other cases you should consider using 'safe_load(stream)'"
  end


# warnings.simplefilter('once', UnsafeLoaderWarning)


  class MantissaNoDotYAML1_1Warning < YAMLWarning
    def initialize(node, flt_str)
        @node = node
        @flt = flt_str
    end

    def to_str
        line = @node.start_mark.line
        col = @node.start_mark.column
        return "
In YAML 1.1 floating point values should have a dot ('.') in their mantissa.
See the Floating-Point Language-Independent Type for YAML™ Version 1.1 specification
( http://yaml.org/type/float.html ). This dot is  !required for JSON nor for YAML 1.2

Correct your float: #{@flt} on line: #{line}, column: #{col}

or alternatively include the following in your code

  import warnings
  warnings.simplefilter('ignore', ruamel.yaml.error.MantissaNoDotYAML1_1Warning)
"
    end
  end

# warnings.simplefilter('once', MantissaNoDotYAML1_1Warning)


  class YAMLFutureWarning < Exception
  end


  class MarkedYAMLFutureWarning < YAMLFutureWarning
    def initialize(
        context: nil,
        context_mark: nil,
        problem: nil,
        problem_mark: nil,
        note: nil,
        warn: nil
    )
        @context = context
        @context_mark = context_mark
        @problem = problem
        @problem_mark = problem_mark
        @note = note
        @warn = warn
    end

    def to_str
      lines = []
      lines.append(@context) if @context

      if c@ontext_mark && (
        @problem.nil? ||
        @problem_mark.nil? ||
        @context_mark.name != @problem_mark.name ||
        @context_mark.line != @problem_mark.line ||
        @context_mark.column != @problem_mark.column
      )
        lines.append(@context_mark.to_str)
      end
      lines.append(@problem) if @problem
      lines.append(@problem_mark.to_str) if @problem_mark
      if @note
        note = textwrap.dedent(@note)
        lines.append(note)
      end
      if @warn
        warn = textwrap.dedent(@warn)
        lines.append(warn)
      end
      lines.join("\n")
    end
  end
end
