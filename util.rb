# encoding: utf-8

# frozen_string_literal: true

"
some helper functions that might be generally useful
"

# import datetime
# from functools import partial
# import re


module SweetStreetYaml
  module Util
    def list(string)
      string.split('')
    end
    module_function :list

# class LazyEval
#     """
#     Lightweight wrapper around lazily evaluated func(*args, **kwargs).
# 
#     func is only evaluated when any attribute of its return value is accessed.
#     Every attribute access is passed through to the wrapped value.
#     (This only excludes special cases like method-wrappers, e.g., __hash__.)
#     The sole additional attribute is the lazy_self function which holds the
#     return value (or, prior to evaluation, func && arguments), in its closure.
#     """
# 
#     def initialize(self, func, *args, **kwargs)
#         # type: (Any, Any, Any) -> nil
#         def lazy_self()
#             # type: () -> Any
#             return_value = func(*args, **kwargs)
#             object.__setattr__(self, 'lazy_self', lambda: return_value)
#             return return_value
# 
#         object.__setattr__(self, 'lazy_self', lazy_self)
# 
#     def __getattribute__(self, name)
#         # type: (Any) -> Any
#         lazy_self = object.__getattribute__(self, 'lazy_self')
#         if name == 'lazy_self'
#             return lazy_self
#         return getattr(lazy_self(), name)
# 
#     def __setattr__(self, name, value)
#         # type: (Any, Any) -> nil
#         setattr(lazy_self(), name, value)
# 
# 
# RegExp = partial(LazyEval, re.compile)

    # TIMESTAMP_REGEXP explictly does not retain extra spaces:
    TIMESTAMP_REGEXP = Regexp.new(
      "^(?<year>[0-9][0-9][0-9][0-9])
       -(?<month>[0-9][0-9]?)
       -(?<day>[0-9][0-9]?)
       (?:((?<t>[Tt])|[ \\t]+)
       (?<hour>[0-9][0-9]?)
       :(?<minute>[0-9][0-9])
       :(?<second>[0-9][0-9])
       (?:\\.(?<fraction>[0-9]*))?
        (?:[ \\t]*(?<tz>Z|(?<tz_sign>[-+])(?<tz_hour>[0-9][0-9]?)
       (?::(?<tz_minute>[0-9][0-9]))?))?)?$",
      Regexp::EXTENDED
    )


    MAX_FRAC = 999999
    def create_timestamp(year, month, day, t, hour = nil, minute = nil, second = nil, fraction = nil, tz = nil, tz_sign = nil, tz_hour = nil, tz_minute = nil)
      # create a timestamp from match against TIMESTAMP_REGEXP
      year = year.to_i
      month = month.to_i
      day = day.to_i
      return Date.new(year, month, day) unless hour

      hour = hour.to_i
      minute = minute.to_i
      second = second.to_i
      frac = 0
      if fraction
        frac_s = fraction[0..6]
        while frac_s.size < 6
          frac_s += '0'
        end
        frac = frac_s.to_i
        frac += 1 if fraction.size > 6 && fraction[6].to_i > 4
        if frac > MAX_FRAC
          fraction = 0
        else
          fraction = frac
        end
      else
        fraction = 0
      end
      delta = nil
      if tz_sign
        tz_hour = tz_hour.to_i
        tz_minute = tz_minute.to_i
        # delta = datetime.timedelta(
        #   hours: tz_hour, minutes: tz_minute, seconds: (frac > MAX_FRAC ? 1 : 0)
        # )
        delta = (tz_hour * 60 + tz_minute) * 60 + (frac > MAX_FRAC ? 1 : 0)
        delta = -delta if tz_sign == '-'
      elsif frac > MAX_FRAC
        delta = -1
      end
      # should do something else instead (or hook this up to the preceding if statement
      # in reverse
      #  if delta .nil?
      #      return datetime.datetime(year, month, day, hour, minute, second, fraction)
      #  return datetime.datetime(year, month, day, hour, minute, second, fraction,
      #                           datetime.timezone.utc)
      # the above is not good enough though, should provide tzinfo. In Python3 that is easily
      # doable drop that kind of support for Python2 as it has not native tzinfo
      data = Time.new(year, month, day, hour, minute, second + fraction * 0.000001)
      data -= delta if delta
      data
    end
    module_function :create_timestamp

    # originally as comment
    # https://github.com/pre-commit/pre-commit/pull/211#issuecomment-186466605
    # if you use this in your code, I suggest adding a test in your test suite
    # that check this routines output against a known piece of your YAML
    # before upgrades to this code break your round-tripped YAML
    def load_yaml_guess_indent(stream, **kw)
      "guess the indent && block sequence indent of yaml stream/string

      returns round_trip_loaded stream, indent level, block sequence indent
      - block sequence indent is the number of spaces before a dash relative to previous indent
      - if there are no block sequences, indent is taken from nested mappings, block sequence
        indent is unset (nil) in that case
      "
      # from .main import YAML
      require 'main'

      if stream.instance_of?(String)
        yaml_str = stream
      elsif stream.instance_of?(Array)
        # most likely, but the Reader checks BOM for this
        yaml_str = stream.decode('utf-8')
      else
        yaml_str = stream.read
      end
      map_indent = nil
      indent = nil  # default if noy found for some reason
      block_seq_indent = nil
      prev_line_key_only = nil
      key_indent = 0
      yaml_str.each_line do |line|
        rline = line.rstrip
        lline = rline.lstrip
        if lline.start_with?('- ')
          l_s = leading_spaces(line)
          block_seq_indent = l_s - key_indent
          idx = l_s + 1
          while line[idx] == ' '  # this will end as we rstripped
            idx += 1
          end
          next if line[idx] == '#'  # comment after -
          indent = idx - key_indent
          break
        end
        if map_indent.nil? && prev_line_key_only && rline
          idx = 0
          while ' -'.include?(line[idx])
            idx += 1
          end
          map_indent = idx - prev_line_key_only if idx > prev_line_key_only
        end
        if rline.end_with?(':')
          key_indent = leading_spaces(line)
          idx = 0
          while line[idx] == ' '  # this will end on ':'
            idx += 1
          end
          prev_line_key_only = idx
          next
        end
        prev_line_key_only = nil
      end
      indent = map_indent if indent.nil? && map_indent
      yaml = YAML.new
      return yaml.load(yaml_str, **kw), indent, block_seq_indent
    end
    module_function :load_yaml_guess_indent


    # load a YAML document, guess the indentation, if you use TABs you are on your own
    def leading_spaces(line)
      idx = 0
      while idx < line.size && line[idx] == ' '
        idx += 1
      end
      idx
    end
    module_function :leading_spaces


    def configobj_walker(cfg)
      "
    walks over a ConfigObj (INI file with comments) generating
    corresponding YAML output (including comments
    "
      # from configobj import ConfigObj

      # raise unless cfg.instance_of?(ConfigObj)
      cfg.initial_comment.each do |c|
        yield c if c.strip
      end
      _walk_section(cfg).each do |s|
        yield s if s.strip
      end
      cfg.final_comment.each do |c|
        yield c if c.strip
      end
    end


    def _walk_section(s, level = 0)
      # from configobj import Section

      # raise unless s.instance_of?(Section)
      indent = '  ' * level
      s.scalars.each do |name|
        s.comments[name].each do |c|
          yield indent + c.strip
        end
        x = s[name]
        if x.include?("\n")
          i = indent + '  '
          x = "|\n" + i + x.strip.gsub("\n", "\n" + i)
        elsif x.include?(':')
          x = "'" + x.gsub("'", "''") + "'"
        end
        line = '{0}{1}: {2}'.format(indent, name, x)
        c = s.inline_comments[name]
        line += ' ' + c if c
        yield line
      end
      s.sections.each do |name|
        s.comments[name].each do |c|
          yield indent + c.strip
        end
        line = '{0}{1}:'.format(indent, name)
        c = s.inline_comments[name]
        line += ' ' + c if c
        yield line
        _walk_section(s[name], level + 1).each { |val| yield val }
      end
    end
  end
end


# def config_obj_2_rt_yaml(cfg)
#     from .comments import CommentedMap, CommentedSeq
#     from configobj import ConfigObj
#     assert isinstance(cfg, ConfigObj)
#     #for c in cfg.initial_comment
#     #    if c.strip()
#     #        pass
#     cm = CommentedMap()
#     for name in s.sections
#         cm[name] = d = CommentedMap()
#
#
#     #for c in cfg.final_comment
#     #    if c.strip()
#     #        yield c
#     return cm
