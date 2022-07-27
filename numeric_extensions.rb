# frozen_string_literal: true

module NumericExtensions
  refine Numeric do
    def to_boolean
      if zero?
        false
      else
        true
      end
    end
  end
end
