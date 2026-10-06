# frozen_string_literal: true

require "a2a"
require "rack"
require "stringio"
require_relative "adapter"

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
          status, headers, body = @sdk.call(normalize_env(env))
          [status, headers.merge("a2a-version" => PROTOCOL_VERSION), body]
        end

        private

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
