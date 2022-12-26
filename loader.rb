# encoding: utf-8

# frozen_string_literal: true

require_relative './reader'
require_relative './scanner'
require_relative './parser'
require_relative './composer'
require_relative './constructor'
require_relative './resolver'

module SweetStreetYaml
  class BaseLoader
    extend Forwardable

    attr_accessor :_reader,
                  :_scanner,
                  :_parser,
                  :_composer,
                  :_constructor,
                  :_resolver,
                  :comment_handling,
                  :version, :tags, :parsed_comments

    def_delegators :@_composer, :check_node, :get_single_node
    def_delegator :@_parser, :dispose
    def_delegator :@_resolver, :processing_version

    def initialize(stream, version = nil, preserve_quotes = nil) # checked
      @comment_handling = nil
      @_reader = Reader.new(stream, self)
      @_scanner = Scanner.new(self)
      @_parser = Parser.new(self)
      @_composer = Composer.new(self)
      @_constructor = BaseConstructor.new(:loader => self)
      @_resolver = VersionedResolver.new(:version => version, :loadumper => self)
    end
  end


  class Loader < BaseLoader # checked
    def initialize(stream, version = nil, preserve_quotes = nil)
      super
      @_constructor = BaseConstructor.new(:loader => self)
    end
  end


  class SafeLoader < Loader
    def initialize(stream, version = nil, preserve_quotes = nil)
      super
      @_constructor = SafeConstructor.new(:loader => self)
    end
  end


  class RoundTripLoader < Loader # checked
    def initialize(stream, version = nil, preserve_quotes = nil)
      super
      @_scanner = RoundTripScanner.new(self)
      @_parser = RoundTripParser.new(self)
      @_constructor = RoundTripConstructor.new(:preserve_quotes => preserve_quotes, :loader => self)
    end
  end
end
