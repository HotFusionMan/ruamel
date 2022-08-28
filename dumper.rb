# encoding: utf-8

# frozen_string_literal: true

# from ruamel.yaml.emitter import Emitter
# from ruamel.yaml.serializer import Serializer
# from ruamel.yaml.representer import (
#     Representer,
#     SafeRepresenter,
#     BaseRepresenter,
#     RoundTripRepresenter,
# )
# from ruamel.yaml.resolver import Resolver, BaseResolver, VersionedResolver
require 'emitter' 
require 'serializer' 
require 'representer' 
require 'resolver' 

module SweetStreetYaml
  class BaseDumper#(Emitter, Serializer, BaseRepresenter, BaseResolver)
    def initialize(
      stream,
      default_style: nil,
      default_flow_style: nil,
      canonical: nil,
      indent: nil,
      width: nil,
      allow_unicode: nil,
      line_break: nil,
      encoding: nil,
      explicit_start: nil,
      explicit_end: nil,
      version: nil,
      tags: nil,
      block_seq_indent: nil,
      top_level_colon_align: nil,
      prefix_colon: nil
    )
      @emitter = Emitter.new(
        stream,
        canonical: canonical,
        indent: indent,
        width: width,
        allow_unicode: allow_unicode,
        line_break: line_break,
        block_seq_indent: block_seq_indent,
        dumper: self
      )
      @serializer = Serializer.new(
        encoding: encoding,
        explicit_start: explicit_start,
        explicit_end: explicit_end,
        version: version,
        tags: tags,
        dumper: self
      )
      @representer = BaseRepresenter.new(
        default_style: default_style,
        default_flow_style: default_flow_style,
        dumper: self
      )
      @resolver = BaseResolver.new(:loadumper => self)
    end
  end


  class SafeDumper#(Emitter, Serializer, SafeRepresenter, Resolver)
    def initialize(
      stream,
      default_style: nil,
      default_flow_style: nil,
      canonical: nil,
      indent: nil,
      width: nil,
      allow_unicode: nil,
      line_break: nil,
      encoding: nil,
      explicit_start: nil,
      explicit_end: nil,
      version: nil,
      tags: nil,
      block_seq_indent: nil,
      top_level_colon_align: nil,
      prefix_colon: nil
    )
      @emitter = Emitter.new(
        stream,
        canonical: canonical,
        indent: indent,
        width: width,
        allow_unicode: allow_unicode,
        line_break: line_break,
        block_seq_indent: block_seq_indent,
        dumper: self
      )
      @serializer = Serializer.new(
        encoding: encoding,
        explicit_start: explicit_start,
        explicit_end: explicit_end,
        version: version,
        tags: tags,
        dumper: self
      )
      @representer = SafeRepresenter.new(
        default_style: default_style,
        default_flow_style: default_flow_style,
        dumper: self
      )
      @resolver = Resolver.new(:loadumper => self)
    end
  end


  class Dumper#(Emitter, Serializer, Representer, Resolver)
    def initialize(
      stream,
      default_style: nil,
      default_flow_style: nil,
      canonical: nil,
      indent: nil,
      width: nil,
      allow_unicode: nil,
      line_break: nil,
      encoding: nil,
      explicit_start: nil,
      explicit_end: nil,
      version: nil,
      tags: nil,
      block_seq_indent: nil,
      top_level_colon_align: nil,
      prefix_colon: nil
    )
      @emitter = Emitter.new(
        stream,
        canonical: canonical,
        indent: indent,
        width: width,
        allow_unicode: allow_unicode,
        line_break: line_break,
        block_seq_indent: block_seq_indent,
        dumper: self
      )
      @serializer = Serializer.new(
        encoding: encoding,
        explicit_start: explicit_start,
        explicit_end: explicit_end,
        version: version,
        tags: tags,
        dumper: self
      )
      @representer = Representer.new(
        default_style: default_style,
        default_flow_style: default_flow_style,
        dumper: self
      )
      @resolver = Resolver.new(:loadumper => self)
    end
  end


  class RoundTripDumper#(Emitter, Serializer, RoundTripRepresenter, VersionedResolver)
    def initialize(
      stream,
      default_style: nil,
      default_flow_style: nil,
      canonical: nil,
      indent: nil,
      width: nil,
      allow_unicode: nil,
      line_break: nil,
      encoding: nil,
      explicit_start: nil,
      explicit_end: nil,
      version: nil,
      tags: nil,
      block_seq_indent: nil,
      top_level_colon_align: nil,
      prefix_colon: nil
    )
      @emitter = Emitter.new(
        stream,
        canonical: canonical,
        indent: indent,
        width: width,
        allow_unicode: allow_unicode,
        line_break: line_break,
        block_seq_indent: block_seq_indent,
        top_level_colon_align: top_level_colon_align,
        prefix_colon: prefix_colon,
        dumper: self
      )
      @serializer = Serializer.new(
        encoding: encoding,
        explicit_start: explicit_start,
        explicit_end: explicit_end,
        version: version,
        tags: tags,
        dumper: self
      )
      @representer = RoundTripRepresenter.new(
        default_style: default_style,
        default_flow_style: default_flow_style,
        dumper: self
      )
      @resolver = VersionedResolver.new(:loader => self)
    end
  end
end
