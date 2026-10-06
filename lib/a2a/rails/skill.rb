# frozen_string_literal: true

module A2A
  module Rails
    class Skill
      attr_reader :id, :name, :description, :tags, :handler, :examples, :input_modes, :output_modes

      def initialize(id:, description:, tags:, handler:, name: nil, examples: nil, input_modes: nil, output_modes: nil)
        @id = normalize_id(id)
        @name = normalize_text(name || humanize_id(@id))
        @description = normalize_optional_text(description)
        @tags = Array(tags).map { |tag| normalize_text(tag) }.freeze
        @handler = handler
        @examples = normalize_optional_collection(examples)
        @input_modes = normalize_optional_collection(input_modes)
        @output_modes = normalize_optional_collection(output_modes)
        freeze
      end

      def validate!
        if @id.to_s.empty?
          raise ConfigurationError, "Skill id must not be empty"
        end

        if @description.nil? || @description.strip.empty?
          raise ConfigurationError, "Skill #{@id.inspect} must define a description"
        end

        if @tags.empty? || @tags.any? { |tag| tag.strip.empty? }
          raise ConfigurationError, "Skill #{@id.inspect} must define at least one non-empty tag"
        end

        validate_optional_strings!(:examples, @examples, allow_empty: true)
        validate_optional_strings!(:input_modes, @input_modes, allow_empty: false)
        validate_optional_strings!(:output_modes, @output_modes, allow_empty: false)

        unless @handler.respond_to?(:call)
          raise InvalidHandlerError, "Handler #{handler_label} must respond to .call"
        end

        self
      end

      private

      def normalize_id(value)
        value.to_sym
      rescue NoMethodError
        raise ConfigurationError, "Skill id must be convertible to a Symbol"
      end

      def normalize_text(value)
        value.to_s.dup.freeze
      end

      def normalize_optional_text(value)
        return if value.nil?

        normalize_text(value)
      end

      def normalize_optional_collection(value)
        return if value.nil?
        return value unless value.is_a?(Array)

        value.map { |entry| entry.is_a?(String) ? entry.dup.freeze : entry }.freeze
      end

      def validate_optional_strings!(field, value, allow_empty:)
        return if value.nil?

        valid = value.is_a?(Array) &&
          (allow_empty || !value.empty?) &&
          value.all? { |entry| entry.is_a?(String) && !entry.strip.empty? }
        return if valid

        requirement = allow_empty ? "an Array of non-empty Strings" : "a non-empty Array of non-empty Strings"
        raise ConfigurationError, "Skill #{@id.inspect} #{field} must be #{requirement}"
      end

      def humanize_id(value)
        value.to_s.split("_").map!(&:capitalize).join(" ")
      end

      def handler_label
        return @handler.name if @handler.respond_to?(:name) && @handler.name

        @handler.inspect
      end
    end
  end
end
