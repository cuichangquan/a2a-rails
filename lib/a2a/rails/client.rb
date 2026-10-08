# frozen_string_literal: true

require "securerandom"
require_relative "client/agent_card_resolver"
require_relative "client/public_types"
require_relative "client/codec"

module A2A
  module Rails
    # Outbound A2A v1.0 Client. Does not require a local Agent, Task Store or
    # server Runtime. This is an unreleased implementation; the production
    # release gates in docs/design/a2a-client-public-api.md still apply.
    class Client
      def initialize(agent_card_url:, allowed_origins:, authorization: nil,
                     credential_origin: nil, card_authorization: nil,
                     card_credential_origin: nil, open_timeout: 3,
                     read_timeout: 10, total_timeout: 15)
        validate_callback!(authorization)
        validate_callback!(card_authorization)
        @policy = OutboundPolicy.new(allowed_origins: allowed_origins)
        card_uri = @policy.validate_url!(agent_card_url)
        # Default each token audience to the explicitly configured card
        # origin. When RPC is advertised on a different origin, callers must
        # explicitly bind the RPC credential to that origin.
        card_origin = origin_for(card_uri)
        rpc_origin = credential_origin || (authorization && card_origin)
        discovery_origin = card_credential_origin || (card_authorization && card_origin)
        check_credential_binding!(authorization, rpc_origin)
        check_credential_binding!(card_authorization, discovery_origin)

        transport = PinnedHttpsTransport.new(
          policy: @policy,
          open_timeout: open_timeout,
          read_timeout: read_timeout,
          total_timeout: total_timeout
        )
        @resolver = AgentCardResolver.new(
          agent_card_url: card_uri.to_s, policy: @policy, transport: transport,
          authorization: authorization, credential_origin: rpc_origin,
          card_authorization: card_authorization,
          card_credential_origin: discovery_origin
        )
      rescue OutboundPolicy::RejectedTarget => error
        raise ConfigurationError.new(error.reason), cause: nil
      rescue PinnedHttpsTransport::Error => error
        raise ConfigurationError.new(error.reason), cause: nil
      end

      def agent_card
        with_errors(:agent_card) { Codec.decode(@resolver.discover.card) }
      end

      def send_message(message:, configuration: nil, metadata: nil)
        with_errors(:send_message) do
          validate_message!(message)
          params = { "message" => Codec.encode(message) }
          params["configuration"] = encode_hash!(configuration, :configuration) unless configuration.nil?
          params["metadata"] = encode_hash!(metadata, :metadata, opaque: true) unless metadata.nil?
          result = rpc(:send_message, "SendMessage", params)
          task = result["task"]
          direct = result["message"]
          unless (task.is_a?(Hash) && direct.nil?) || (direct.is_a?(Hash) && task.nil?)
            raise InvalidResponseError.new(:invalid_send_result, operation: :send_message)
          end

          if task
            SendResult.new(kind: :task, task: normalize_task!(task, :send_message), message: nil).freeze
          else
            SendResult.new(kind: :message, task: nil, message: normalize_message!(direct, :send_message)).freeze
          end
        end
      end

      def get_task(id:, history_length: nil)
        with_errors(:get_task) do
          params = { "id" => required_text!(id, :id) }
          params["historyLength"] = nonnegative_integer!(history_length, :history_length) unless history_length.nil?
          normalize_task!(rpc(:get_task, "GetTask", params), :get_task)
        end
      end

      def list_tasks(context_id: nil, status: nil, page_size: nil, page_token: nil,
                     history_length: nil, status_timestamp_after: nil, include_artifacts: nil)
        with_errors(:list_tasks) do
          params = {}
          params["contextId"] = required_text!(context_id, :context_id) unless context_id.nil?
          params["status"] = required_text!(status, :status) unless status.nil?
          unless page_size.nil?
            raise InvalidInputError, :page_size unless page_size.is_a?(Integer) && page_size.between?(1, 100)
            params["pageSize"] = page_size
          end
          params["pageToken"] = string_value!(page_token, :page_token) unless page_token.nil?
          params["historyLength"] = nonnegative_integer!(history_length, :history_length) unless history_length.nil?
          params["statusTimestampAfter"] = required_text!(status_timestamp_after, :status_timestamp_after) unless status_timestamp_after.nil?
          unless include_artifacts.nil?
            raise InvalidInputError, :include_artifacts unless include_artifacts == true || include_artifacts == false
            params["includeArtifacts"] = include_artifacts
          end

          raw = rpc(:list_tasks, "ListTasks", params)
          unless raw["tasks"].is_a?(Array) &&
              raw["nextPageToken"].is_a?(String) &&
              raw["pageSize"].is_a?(Integer) && raw["pageSize"] >= 0 &&
              raw["totalSize"].is_a?(Integer) && raw["totalSize"] >= 0
            raise InvalidResponseError.new(:invalid_page, operation: :list_tasks)
          end
          tasks = raw["tasks"].map { |value| normalize_task!(value, :list_tasks) }.freeze
          ListResult.new(tasks: tasks,
                         next_page_token: raw.fetch("nextPageToken").dup.freeze,
                         page_size: raw.fetch("pageSize"),
                         total_size: raw.fetch("totalSize")).freeze
        end
      end

      def cancel_task(id:, metadata: nil)
        with_errors(:cancel_task) do
          params = { "id" => required_text!(id, :id) }
          params["metadata"] = encode_hash!(metadata, :metadata, opaque: true) unless metadata.nil?
          normalize_task!(rpc(:cancel_task, "CancelTask", params), :cancel_task)
        end
      end

      private

      def rpc(operation, name, params)
        @resolver.rpc(method: name, params: params, id: SecureRandom.uuid)
      end

      def normalize_task!(value, operation)
        unless value.is_a?(Hash) && text?(value["id"]) &&
            value["status"].is_a?(Hash) && text?(value["status"]["state"])
          raise InvalidResponseError.new(:invalid_task, operation: operation)
        end
        Codec.decode(value)
      end

      def normalize_message!(value, operation)
        unless value.is_a?(Hash) && text?(value["messageId"]) &&
            text?(value["role"]) && value["parts"].is_a?(Array) && !value["parts"].empty?
          raise InvalidResponseError.new(:invalid_message, operation: operation)
        end
        Codec.decode(value)
      end

      def validate_message!(message)
        unless message.is_a?(Hash) && text?(field(message, :message_id, "messageId")) &&
            field(message, :role, "role") == "ROLE_USER" &&
            (parts = field(message, :parts, "parts")).is_a?(Array) && !parts.empty?
          raise InvalidInputError, :message
        end
        parts.each do |part|
          raise InvalidInputError, :part unless part.is_a?(Hash)
          count = %w[text raw url data].count { |key| part.key?(key) || part.key?(key.to_sym) }
          raise InvalidInputError, :part_oneof unless count == 1
        end
      end

      def field(hash, key, wire)
        raise InvalidInputError, :ambiguous_protocol_key if hash.key?(key) && hash.key?(wire)
        hash.key?(key) ? hash[key] : (hash.key?(wire) ? hash[wire] : hash[key.to_s])
      end

      def encode_hash!(value, label, opaque: false)
        raise InvalidInputError, label unless value.is_a?(Hash)
        Codec.encode(value, opaque: opaque)
      end

      def text?(value)
        value.is_a?(String) && !value.empty? && !value.strip.empty?
      end

      def required_text!(value, name)
        raise InvalidInputError, name unless text?(value)
        value
      end

      def string_value!(value, name)
        raise InvalidInputError, name unless value.is_a?(String)
        value
      end

      def nonnegative_integer!(value, name)
        raise InvalidInputError, name unless value.is_a?(Integer) && value >= 0
        value
      end

      def origin_for(uri)
        uri.port == 443 ? "https://#{uri.host}" : "https://#{uri.host}:#{uri.port}"
      end

      def validate_callback!(callback)
        raise ConfigurationError, :credential_callback unless callback.nil? || callback.respond_to?(:call)
      end

      def check_credential_binding!(callback, origin)
        if callback && (!origin.is_a?(String) || origin.empty?)
          raise ConfigurationError, :credential_origin
        end
        raise ConfigurationError, :credential_origin unless callback || origin.nil?
      end

      def with_errors(operation)
        yield
      rescue Error
        raise
      rescue AgentCardResolver::UnsupportedInterface => error
        raise UnsupportedInterfaceError.new(error.reason, operation: operation), cause: nil
      rescue AgentCardResolver::InvalidCard, AgentCardResolver::Error => error
        raise DiscoveryError.new(error.reason, operation: operation), cause: nil
      rescue AgentCardResolver::RemoteError => error
        raise RemoteError.new(error.code, operation: operation), cause: nil
      rescue PinnedHttpsTransport::DeadlineExceeded
        raise TimeoutError.new(operation: operation,
                               may_have_executed: %i[send_message cancel_task].include?(operation)), cause: nil
      rescue PinnedHttpsTransport::HTTPError => error
        if [401, 403].include?(error.status)
          raise AuthenticationError.new(error.status, operation: operation), cause: nil
        end
        raise TransportError.new(:http_error, operation: operation), cause: nil
      rescue PinnedHttpsTransport::InvalidResponse, PinnedHttpsTransport::ResponseTooLarge => error
        raise InvalidResponseError.new(error.reason, operation: operation), cause: nil
      rescue PinnedHttpsTransport::Error, OutboundPolicy::RejectedTarget => error
        raise TransportError.new(error.reason, operation: operation), cause: nil
      end
    end
  end
end
