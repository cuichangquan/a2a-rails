# frozen_string_literal: true

module A2A
  module Rails
    class Skill
      attr_reader :id, :name, :description, :tags, :handler

      def initialize(id:, description:, tags:, handler:, name: nil)
        @id = normalize_id(id)
        @name = normalize_text(name || humanize_id(@id))
        @description = normalize_optional_text(description)
        @tags = Array(tags).map { |tag| normalize_text(tag) }.freeze
        @handler = handler
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
