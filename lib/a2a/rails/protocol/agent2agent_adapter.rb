# frozen_string_literal: true

require "a2a"
require "rack"
require "stringio"
require_relative "adapter"
require_relative "task_mapper"

module A2A
  module Rails
    module Protocol
      class Agent2AgentAdapter < Adapter
        PROTOCOL_VERSION = "1.0"
        SUPPORTED_OPERATIONS = %w[SendMessage GetTask ListTasks CancelTask].freeze
        RESPONSE_SCHEMAS = {
          "SendMessage" => "Send Message Response",
          "GetTask" => "Task",
          "ListTasks" => "List Tasks Response",
          "CancelTask" => "Task"
        }.freeze

        def initialize(agent_card:, request_handler:, sdk_factory: nil)
          unless request_handler.respond_to?(:call)
            raise ArgumentError, "request_handler must respond to #call"
          end

          @request_handler = request_handler
          factory = sdk_factory || A2A.method(:agent)
          @sdk = factory.call(agent_card: agent_card) { |env| dispatch(env) }
        end

        def call(env)
          status, headers, body = with_sensitive_sdk_logging_suppressed do
            @sdk.call(normalize_env(env))
          end
          [status, headers.merge("a2a-version" => PROTOCOL_VERSION), body]
        end

        private

        def with_sensitive_sdk_logging_suppressed
          return yield unless defined?(::Console) && ::Console.respond_to?(:logger)
          return yield unless defined?(::Console::Logger::WARN) && defined?(::A2A::Server::Triage)

          logger = ::Console.logger
          return yield unless logger.respond_to?(:subjects)

          subjects = logger.subjects
          triage = ::A2A::Server::Triage
          had_override = subjects.key?(triage)
          previous_level = subjects[triage]
          subjects[triage] = ::Console::Logger::WARN

          yield
        ensure
          if defined?(subjects) && subjects
            if had_override
              subjects[triage] = previous_level
            else
              subjects.delete(triage)
            end
          end
        end

        def normalize_env(env)
          input = env.fetch("rack.input")
          env.merge(
            "PATH_INFO" => "/",
            "rack.input" => StringIO.new(input.read.to_s)
          )
        end

        def dispatch(env)
          validate_version!(env)

          operation = env.fetch("a2a.operation")
          raise A2A::UnsupportedOperationError.new unless SUPPORTED_OPERATIONS.include?(operation)

          request = env.fetch("a2a.request")
          validate_request!(request)

          result = @request_handler.call(operation: operation, params: request.to_h)
          schema(RESPONSE_SCHEMAS.fetch(operation), result)
        rescue A2A::Rails::TaskNotFoundError => error
          raise A2A::TaskNotFoundError.new(error.task_id)
        rescue A2A::Rails::TaskNotCancelableError => error
          raise A2A::TaskNotCancelableError.new(
            error.task_id,
            state: TaskMapper.wire_state(error.state)
          )
        rescue A2A::Rails::InvalidRequestError,
          A2A::Rails::InvalidTaskQueryError,
          A2A::Rails::InvalidTaskStateError => error
          raise A2A::InvalidParamsError.new(error.message)
        rescue A2A::Rails::ContentTypeNotSupportedError
          raise A2A::ContentTypeNotSupportedError.new
        rescue A2A::Rails::TaskContinuationNotSupportedError => error
          raise A2A::UnsupportedOperationError.new(message: error.message)
        end

        def validate_version!(env)
          version = env["HTTP_A2A_VERSION"]
          if version.nil? || version.empty?
            version = Rack::Utils.parse_query(env["QUERY_STRING"].to_s)["A2A-Version"]
          end
          version = "0.3" if version.nil? || version.empty?

          raise A2A::VersionNotSupportedError.new(version) unless version == PROTOCOL_VERSION
        end

        def validate_request!(request)
          request.valid!
        rescue A2A::Protocol::JsonSchema::ValidationError
          raise A2A::InvalidParamsError.new("Invalid request parameters")
        end

        def schema(name, value)
          object = A2A::Protocol::JsonSchema[name].new(value)
          object.valid!
          object
        end
      end
    end
  end
end
