# encoding: utf-8

# frozen_string_literal: true

# import datetime
# import copy

# ToDo: at least on PY3 you could probably attach the tzinfo correctly to the object
#       a more complete datetime might be used by safe loading as well

module SweetStreetYaml
  class TimeStamp #< DateTime
    def initialize(*args, **kw)
      @ts = DateTime.new(*args, **kw)
      @_yaml = { :t => false, :tz => nil, :delta => 0 }
    end
    attr_accessor :_yaml

    def self.deep_dup
      ts = TimeStamp.new(@year, @month, @day, @hour, @minute, @second, @microsecond, @tzinfo, @fold)
      ts._yaml = @_yaml.deep_dup
      ts
    end

    def replace(
      year = nil,
      month = nil,
      day = nil,
      hour = nil,
      minute = nil,
      second = nil,
      microsecond = nil,
      tzinfo = true,
      fold: nil
    )
      @year ||= year
      @month ||= month
      @day ||= day
      @hour ||= hour
      @minute ||= minute
      @second ||= second
      @microsecond ||= microsecond
      @tzinfo = tzinfo if tzinfo
      @fold ||= fold
      @ts = self.class.new(@year, @month, @day, @hour, @minute, @second, @microsecond, @tzinfo, :fold => fold)
      @ts._yaml = @_yaml.deep_dup
      @ts
    end
  end
end
