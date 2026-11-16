# frozen_string_literal: true

require "json"

module A2A
  module Rails
    # A normal, non-terminal Handler outcome. Never inferred from a Hash key.
    class InputRequired
      attr_reader :text

      def initialize(text, data: nil)
        unless text.is_a?(String) && !text.strip.empty?
          raise ArgumentError, "InputRequired text must be a nonempty String"
        end
        unless data.nil? || data.is_a?(Hash)
          raise ArgumentError, "InputRequired data must be a JSON object"
        end
        @text = text.dup.freeze
        @data = data.nil? ? nil : copy_json(data)
        freeze
      end

      def parts
        result = [{ text: @text.dup }]
        result << { data: copy_json(@data), media_type: "application/json" } unless @data.nil?
        result
      end

      private

      def copy_json(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), result|
            raise ArgumentError, "InputRequired JSON keys must be Strings" unless key.is_a?(String)
            result[key.dup] = copy_json(nested)
          end
        when Array then value.map { |item| copy_json(item) }
        when String then value.dup
        when Integer, TrueClass, FalseClass, NilClass then value
        when Float
          raise ArgumentError, "InputRequired JSON numbers must be finite" unless value.finite?
          value
        else
          raise ArgumentError, "InputRequired data must contain JSON values"
        end
      end
    end
  end
end
