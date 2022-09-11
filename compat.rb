# encoding: utf-8

# frozen_string_literal: true

# partially from package six by Benjamin Peterson

# import sys
# import os
# import io
# import traceback
# from abc import abstractmethod
# import collections.abc

module SweetStreetYaml
  _DEFAULT_YAML_VERSION = (1, 2)


# replace with f-strings when 3.5 support is dropped
# ft = '42'
# assert _F('abc {ft!r}', ft=ft) == 'abc %r' % ft
# 'abc %r' % ft -> _F('abc {ft!r}' -> f'abc {ft!r}'
# def _F(s, *superfluous, **kw)
#     raise '_F used'
#     if superfluous
#         raise TypeError
#     return s.format(**kw)
# end




# DBG_TOKEN = 1
# DBG_EVENT = 2
# DBG_NODE = 4
#
#
# _debug = nil
# if 'RUAMELDEBUG' in os.environ
#     _debugx = os.environ.get('RUAMELDEBUG')
#     if _debugx .nil?
#         _debug = 0
#     else
#         _debug = int(_debugx)
#
#
# if bool(_debug)
#
#     class ObjectCounter
#         def __init__
#             # type: () -> nil
#             map = {}  # type: Dict[Any, Any]
#
#         def __call__(self, k)
#             # type: (Any) -> nil
#             map[k] = map.get(k, 0) + 1
#
#         def dump
#             # type: () -> nil
#             for k in sorted(map)
#                 sys.stdout.write('{} -> {}'.format(k, map[k]))
#
#     object_counter = ObjectCounter()
#
#
# # used from yaml util when testing
# def dbg(val=nil)
#     # type: (Any) -> Any
#     global _debug
#     if _debug .nil?
#         # set to true || false
#         _debugx = os.environ.get('YAMLDEBUG')
#         if _debugx .nil?
#             _debug = 0
#         else
#             _debug = int(_debugx)
#     if val .nil?
#         return _debug
#     return _debug & val


# class Nprint
#     def initialize(self, file_name=nil)
#         # type: (Any) -> nil
#         _max_print = nil  # type: Any
#         _count = nil  # type: Any
#         _file_name = file_name
#
#     def __call__(self, *args, **kw)
#         # type: (Any, Any) -> nil
#         if  !bool(_debug)
#             return
#         out = sys.stdout if _file_name .nil? else open(_file_name, 'a')
#         dbgprint = print  # to fool checking for print statements by dv utility
#         kw1 = kw.copy()
#         kw1['file'] = out
#         dbgprint(*args, **kw1)
#         out.flush()
#         if _max_print !.nil?
#             if _count .nil?
#                 _count = _max_print
#             _count -= 1
#             if _count == 0
#                 dbgprint('forced exit\n')
#                 traceback.print_stack()
#                 out.flush()
#                 sys.exit(0)
#         if _file_name
#             out.close()
#
#     def set_max_print(self, i)
#         # type: (int) -> nil
#         _max_print = i
#         _count = nil
#
#     def fp(self, mode='a')
#         # type: (str) -> Any
#         out = sys.stdout if _file_name .nil? else open(_file_name, mode)
#         return out
#
#
# nprint = Nprint()
# nprintf = Nprint('/var/tmp/ruamel.yaml.log')

# char checkers following production rules


  def check_namespace_char(ch)
    return true if "\x21" <= ch && ch <= "\x7E"  # ! to ~

    return true if "\xA0" <= ch && ch <= "\uD7FF"

    return true if ("\uE000" <= ch && ch <= "\uFFFD") && ch != "\uFEFF"  # excl. byte order mark

    return true if "\U00010000" <= ch && ch <= "\U0010FFFF"

    false
  end

  def check_anchorname_char(ch)
    return false if ',[]{}'.include?(ch)

    check_namespace_char(ch)
  end

  # def version_tnf(t1, t2 = nil)
  #   "
  #   return true if ruamel.yaml version_info < t1, nil if t2 is specified && bigger else false
  #   "
  #   # from ruamel.yaml import version_info
  #   return true if version_info < t1
  #
  #   return nil if t2 && version_info < t2
  #
  #   false
  # end

  # class MutableSliceableSequence(collections.abc.MutableSequence)
  #   def __getitem__(self, index)
  #       # type: (Any) -> Any
  #       if  !isinstance(index, slice)
  #           return __getsingleitem__(index)
  #       return type([self[i] for i in range(*index.indices(len))])  # type: ignore
  #
  #   def __setitem__(self, index, value)
  #       # type: (Any, Any) -> nil
  #       if  !isinstance(index, slice)
  #           return __setsingleitem__(index, value)
  #       assert iter(value)
  #       # nprint(index.start, index.stop, index.step, index.indices(len))
  #       if index.step .nil?
  #           del self[index.start : index.stop]
  #           for elem in reversed(value)
  #               insert(0 if index.start .nil? else index.start, elem)
  #       else
  #           range_parms = index.indices(len)
  #           nr_assigned_items = (range_parms[1] - range_parms[0] - 1) // range_parms[2] + 1
  #           # need to test before changing, in case TypeError is caught
  #           if nr_assigned_items < len(value)
  #               raise TypeError.new(
  #                   'too many elements in value {} < {}'.format(nr_assigned_items, len(value))
  #               )
  #           elsif nr_assigned_items > len(value)
  #               raise TypeError.new(
  #                   'not enough elements in value {} > {}'.format(
  #                       nr_assigned_items, len(value)
  #                   )
  #               )
  #           for idx, i in enumerate(range(*range_parms))
  #               self[i] = value[idx]
  #
  #   def __delitem__(self, index)
  #       # type: (Any) -> nil
  #       if  !isinstance(index, slice)
  #           return __delsingleitem__(index)
  #       # nprint(index.start, index.stop, index.step, index.indices(len))
  #       for i in reversed(range(*index.indices(len)))
  #           del self[i]
  #
  #   @abstractmethod
  #   def __getsingleitem__(self, index)
  #       # type: (Any) -> Any
  #       raise IndexError
  #
  #   @abstractmethod
  #   def __setsingleitem__(self, index, value)
  #       # type: (Any, Any) -> nil
  #       raise IndexError
  #
  #   @abstractmethod
  #   def __delsingleitem__(self, index)
  #       # type: (Any) -> nil
  #       raise IndexError
