# frozen_string_literal: true

module A2A
  module Rails
    module Protocol
      class RequestHandler
        def initialize(dispatcher:, lifecycle:, task_mapper: TaskMapper.new)
          @dispatcher = dispatcher
          @lifecycle = lifecycle
          @task_mapper = task_mapper
        end

        def call(operation:, params:)
          validate_common!(params)

          case operation
          when "SendMessage"
            send_message(params)
          when "GetTask"
            get_task(params)
          when "ListTasks"
            list_tasks(params)
          when "CancelTask"
            cancel_task(params)
          else
            raise InvalidRequestError, "Unsupported operation: #{operation}"
          end
        end

        private

        def send_message(params)
          @dispatcher.validate!
          history_length = history_length(params)
          message, context_id = normalize_message(params)

          task = @lifecycle.create(message: message, context_id: context_id)
          @lifecycle.start(task.fetch(:id))
          context = { task_id: task.fetch(:id), context_id: task.fetch(:context_id) }

          task = begin
            result = @dispatcher.call(message: message, context: context)
            @lifecycle.complete(task.fetch(:id), result)
          rescue RejectedTask => error
            @lifecycle.reject(task.fetch(:id), error)
          rescue StandardError => error
            @lifecycle.fail(task.fetch(:id), error)
          end

          { "task" => @task_mapper.dump(task, history_length: history_length, include_artifacts: true) }
        end

        def get_task(params)
          history_length = history_length(params)
          task = @lifecycle.find(required_id(params))
          @task_mapper.dump(task, history_length: history_length, include_artifacts: true)
        end

        def list_tasks(params)
          history_length = history_length(params)
          validate_list_filters!(params)
          filters = {}
          filters[:context_id] = params["contextId"] if params.key?("contextId")
          filters[:status] = @task_mapper.internal_state(params["status"]) if params.key?("status")
          filters[:status_timestamp_after] = params["statusTimestampAfter"] if params.key?("statusTimestampAfter")
          filters[:page_size] = params["pageSize"] if params.key?("pageSize")
          filters[:page_token] = params["pageToken"] if params.key?("pageToken")

          result = @lifecycle.list(**filters)
          include_artifacts = params["includeArtifacts"] == true

          {
            "tasks" => result.fetch(:tasks).map do |task|
              @task_mapper.dump(task, history_length: history_length, include_artifacts: include_artifacts)
            end,
            "totalSize" => result.fetch(:total_size),
            "pageSize" => result.fetch(:page_size),
            "nextPageToken" => result.fetch(:next_page_token)
          }
        end

        def cancel_task(params)
          task = @lifecycle.cancel(required_id(params))
          @task_mapper.dump(task, include_artifacts: true)
        end

        def normalize_message(params)
          raw = params["message"]
          unless raw.is_a?(Hash)
            raise InvalidRequestError, "message is required"
          end

          message_id = raw["messageId"]
          unless message_id.is_a?(String) && !message_id.empty?
            raise InvalidRequestError, "messageId is required"
          end

          unless raw["role"] == "ROLE_USER"
            raise InvalidRequestError, "ROLE_USER is required"
          end

          parts = raw["parts"]
          unless parts.is_a?(Array) && !parts.empty?
            raise InvalidRequestError, "nonempty parts are required"
          end

          task_id = raw["taskId"]
          if !task_id.nil? && !task_id.is_a?(String)
            raise InvalidRequestError, "taskId must be a String"
          end
          context_id = raw["contextId"]
          if !context_id.nil? && !context_id.is_a?(String)
            raise InvalidRequestError, "contextId must be a String"
          end
          metadata = raw["metadata"]
          unless metadata.nil? || metadata.is_a?(Hash)
            raise InvalidRequestError, "message metadata must be an object"
          end

          if task_id.is_a?(String) && !task_id.empty?
            @lifecycle.find(task_id)
            raise TaskContinuationNotSupportedError, "Task continuation is not supported in v0.1"
          end

          normalized_parts = parts.map { |part| normalize_text_part(part) }
          message = {
            message_id: message_id,
            role: :user,
            parts: normalized_parts,
            metadata: copy(metadata || {})
          }

          [message, context_id]
        end

        def normalize_text_part(part)
          unless part.is_a?(Hash) && part["text"].is_a?(String) && (part.keys & %w[data raw url]).empty?
            raise ContentTypeNotSupportedError, "Only text Parts are supported in v0.1"
          end
          media_type = part["mediaType"]
          unless media_type.nil? || media_type.is_a?(String)
            raise InvalidRequestError, "mediaType must be a String"
          end
          metadata = part["metadata"]
          unless metadata.nil? || metadata.is_a?(Hash)
            raise InvalidRequestError, "part metadata must be an object"
          end

          normalized = {
            text: part["text"],
            media_type: part["mediaType"].to_s.empty? ? "text/plain" : part["mediaType"]
          }
          normalized[:metadata] = copy(metadata) if metadata
          normalized
        end

        def validate_list_filters!(params)
          if params.key?("contextId") && !params["contextId"].nil? && !params["contextId"].is_a?(String)
            raise InvalidRequestError, "contextId must be a String"
          end
          if params.key?("pageToken") && !params["pageToken"].is_a?(String)
            raise InvalidRequestError, "pageToken must be a String"
          end
          if params.key?("includeArtifacts") && ![true, false].include?(params["includeArtifacts"])
            raise InvalidRequestError, "includeArtifacts must be boolean"
          end
        end

        def required_id(params)
          id = params["id"]
          unless id.is_a?(String) && !id.empty?
            raise InvalidRequestError, "id is required"
          end

          id
        end

        def history_length(params)
          return nil unless params.key?("historyLength")

          value = params["historyLength"]
          unless value.is_a?(Integer) && value >= 0
            raise InvalidRequestError, "historyLength must be a nonnegative integer"
          end

          value
        end

        def validate_common!(params)
          unless params.is_a?(Hash)
            raise InvalidRequestError, "params must be an object"
          end

          tenant = params["tenant"]
          if tenant && !tenant.to_s.empty?
            raise InvalidRequestError, "tenant is not supported in v0.1"
          end
        end

        def copy(value)
          Marshal.load(Marshal.dump(value))
        end
      end
    end
  end
end
