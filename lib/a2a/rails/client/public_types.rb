# frozen_string_literal: true

module A2A
  module Rails
    class Client
      # Public client-only exceptions. Never include response bodies, URLs,
      # request metadata or credential strings in exception messages.
      class Error < A2A::Rails::Error
        attr_reader :reason, :operation

        def initialize(reason, operation: nil)
          @reason = reason
          @operation = operation
          super("Outbound A2A #{operation || 'Client'}: #{reason}")
        end
      end

      class ConfigurationError < Error; end
      class InvalidInputError < Error; end
      class DiscoveryError < Error; end
      class UnsupportedInterfaceError < DiscoveryError; end
      class TransportError < Error; end

      class TimeoutError < TransportError
        attr_reader :may_have_executed

        def initialize(operation:, may_have_executed:)
          @may_have_executed = may_have_executed
          super(:timeout, operation: operation)
        end
      end

      class AuthenticationError < Error
        attr_reader :status

        def initialize(status, operation:)
          @status = status
          super(:authentication_rejected, operation: operation)
        end
      end

      class RemoteError < Error
        attr_reader :code

        def initialize(code, operation:)
          @code = code
          super(:remote_protocol_error, operation: operation)
        end
      end

      class InvalidResponseError < Error; end

      # Immutable plain-Ruby results, deliberately independent of the SDK.
      SendResult = Struct.new(:kind, :task, :message, keyword_init: true)
      ListResult = Struct.new(:tasks, :next_page_token, :page_size, :total_size, keyword_init: true)
    end
  end
end
