# frozen_string_literal: true

module A2A
  module Rails
    module Protocol
      # Local compatibility boundary for agent2agent 2.0's recursive nil
      # compaction. Protocol fields still use the SDK's normalization; only
      # Part content is restored from the original plain-Ruby representation.
      # In particular, this does not change metadata serialization.
      module PartData
        CONTENT_FIELDS = %w[text data raw url].freeze

        module_function

        def restore_request(params, original)
          return params unless params.is_a?(Hash) && original.is_a?(Hash)

          restore_message(params["message"], original["message"], request: true)
          params
        end

        def restore_response(name, normalized, original)
          case name
          when "Send Message Response"
            restore_message(normalized["message"], original["message"])
            restore_task(normalized["task"], original["task"])
          when "Task"
            restore_task(normalized, original)
          when "List Tasks Response"
            each_pair(normalized["tasks"], original["tasks"]) do |task, source|
              restore_task(task, source)
            end
          end
          normalized
        end

        def restore_task(task, original)
          return unless task.is_a?(Hash) && original.is_a?(Hash)

          each_pair(task["history"], original["history"]) do |message, source|
            restore_message(message, source)
          end
          each_pair(task["artifacts"], original["artifacts"]) do |artifact, source|
            restore_message(artifact, source)
          end
          status = task["status"]
          source_status = original["status"]
          if status.is_a?(Hash) && source_status.is_a?(Hash)
            restore_message(status["message"], source_status["message"])
          end
        end

        def restore_message(message, original, request: false)
          return unless message.is_a?(Hash) && original.is_a?(Hash)

          each_pair(message["parts"], original["parts"]) do |part, source|
            next unless part.is_a?(Hash) && source.is_a?(Hash)

            # Preserve original kind-field presence so the Rails input contract
            # can reject ambiguous Parts even when one field is JSON null.
            fields = request ? CONTENT_FIELDS : ["data"]
            fields.each { |field| part[field] = copy(source[field]) if source.key?(field) }
            next unless request && source.key?("data")

            # Accept the same alternate spelling as the SDK, but avoid
            # choosing a Data media type based on field order.
            keys = %w[mediaType media_type].select { |key| source.key?(key) }
            if keys.size > 1
              raise InvalidRequestError, "Data Part must not specify mediaType more than once"
            end
            part["mediaType"] = source.fetch(keys.first) if keys.one?
          end
        end

        def each_pair(values, originals)
          return unless values.is_a?(Array) && originals.is_a?(Array)

          values.each_with_index { |value, index| yield value, originals[index] }
        end

        def copy(value)
          Marshal.load(Marshal.dump(value))
        end

        private_class_method :restore_task, :restore_message, :each_pair, :copy
      end
    end
  end
end
