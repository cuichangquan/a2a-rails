# frozen_string_literal: true

require_relative "pinned_https_transport"

module A2A
  module Rails
    class Client
      # Internal A2A v1.0 JSON-RPC Agent Card discovery and RPC boundary.
      #
      # NOT a public Client facade: application authentication, DTO contracts,
      # complete schema validation and multi-language HTTP integration follow
      # in later Step 29 PRs. Default construction always uses the secure
      # OutboundPolicy and PinnedHttpsTransport; injection is test-only.
      class AgentCardResolver
        class Error < A2A::Rails::Error
          attr_reader :reason

          def initialize(reason)
            @reason = reason
            super("Outbound A2A Agent Card rejected: #{reason}")
          end
        end

        class InvalidCard < Error; end
        class UnsupportedInterface < Error; end
        class InvalidRPC < Error; end

        class RemoteError < Error
          attr_reader :code

          def initialize(code)
            @code = code
            super(:remote_json_rpc_error)
          end
        end

        Interface = Struct.new(:url, :tenant, keyword_init: true)
        Discovery = Struct.new(:card, :interface, keyword_init: true)

        JSONRPC_BINDING = "JSONRPC"
        PROTOCOL_VERSION = "1.0"
        METHODS = %w[SendMessage GetTask ListTasks CancelTask].freeze
        MAX_INTERFACES = 64
        MAX_SKILLS = 256

        def initialize(agent_card_url:, allowed_origins: nil,
                       card_authorization: nil, card_credential_origin: nil,
                       authorization: nil, credential_origin: nil,
                       policy: nil, transport: nil)
          # Production callers must construct through the forthcoming public
          # Client facade, which will not expose policy/transport overrides.
          @policy = policy || OutboundPolicy.new(allowed_origins: allowed_origins)
          @transport = transport || PinnedHttpsTransport.new(policy: @policy)
          @agent_card_url = agent_card_url
          @card_authorization = card_authorization
          @card_credential_origin = card_credential_origin
          @authorization = authorization
          @credential_origin = credential_origin
        end

        # Re-fetch on each invocation; never share card/identity cache.
        # The transport separately resolves and pins the card destination.
        def discover
          response = @transport.get_json(
            url: @agent_card_url,
            authorization: @card_authorization,
            credential_origin: @card_credential_origin
          )
          card = response.json
          validate_card!(card)
          interface = choose_interface!(card.fetch("supportedInterfaces"))
          Discovery.new(card: deep_freeze(card), interface: interface).freeze
        end

        # A thin INTERNAL wire operation, not the public SendMessage API.
        # The supplied params use JSON/protocol camelCase, not Ruby DTO keys.
        def rpc(method:, params:, id:)
          unless METHODS.include?(method) && params.is_a?(Hash) &&
              params.keys.all? { |key| key.is_a?(String) } &&
              !params.key?("tenant") &&
              (id.is_a?(String) && !id.empty? || id.is_a?(Integer))
            raise InvalidRPC, :invalid_parameters
          end

          interface = discover.interface
          request_params = params.dup
          # A2A 1.0 puts the opaque tenant in the request's params, not the
          # JSON-RPC envelope. The host is forbidden from overriding it.
          request_params["tenant"] = interface.tenant unless interface.tenant.nil?
          wire = {
            "jsonrpc" => "2.0",
            "id" => id,
            "method" => method,
            "params" => request_params
          }
          response = @transport.post_json(
            url: interface.url, json: wire,
            authorization: @authorization,
            credential_origin: @credential_origin
          )
          envelope = response.json
          unless envelope.is_a?(Hash) && envelope["jsonrpc"] == "2.0" &&
              envelope["id"] == id &&
              (envelope.key?("result") ^ envelope.key?("error"))
            raise InvalidRPC, :invalid_envelope
          end
          if envelope.key?("error")
            error = envelope["error"]
            raise InvalidRPC, :invalid_envelope unless error.is_a?(Hash) && error["code"].is_a?(Integer)

            # The remote error.message/data are untrusted, and may contain
            # secrets. Never reflect them in exception messages or logs.
            raise RemoteError, error.fetch("code")
          end

          raise InvalidRPC, :invalid_result unless envelope["result"].is_a?(Hash)

          deep_freeze(envelope.fetch("result"))
        end

        private

        def validate_card!(card)
          unless card.is_a?(Hash) &&
              %w[name description version].all? { |key| present_text?(card[key]) } &&
              card["capabilities"].is_a?(Hash) &&
              valid_mode_list?(card["defaultInputModes"]) &&
              valid_mode_list?(card["defaultOutputModes"]) &&
              card["skills"].is_a?(Array) && !card["skills"].empty? &&
              card["skills"].size <= MAX_SKILLS &&
              card["skills"].all? { |s| s.is_a?(Hash) && present_text?(s["id"]) } &&
              card["supportedInterfaces"].is_a?(Array) &&
              !card["supportedInterfaces"].empty? &&
              card["supportedInterfaces"].size <= MAX_INTERFACES
            raise InvalidCard, :invalid_card_shape
          end

          card.fetch("supportedInterfaces").each do |item|
            unless item.is_a?(Hash) &&
                present_text?(item["url"]) &&
                present_text?(item["protocolBinding"]) &&
                present_text?(item["protocolVersion"])
              raise InvalidCard, :invalid_interface_shape
            end
          end
        end

        def choose_interface!(interfaces)
          candidate = interfaces.find do |entry|
            entry["protocolBinding"] == JSONRPC_BINDING &&
              entry["protocolVersion"] == PROTOCOL_VERSION
          end
          raise UnsupportedInterface, :no_jsonrpc_v1_interface unless candidate

          if candidate.key?("tenant") &&
              (!candidate["tenant"].is_a?(String) || candidate["tenant"].bytesize > 512)
            raise InvalidCard, :invalid_tenant
          end

          # Validate the UNTRUSTED card's selected endpoint independently of
          # card origin; no guessed path, origin fallback or automatic retry.
          target = @policy.resolve!(candidate.fetch("url"))
          Interface.new(url: target.url, tenant: candidate["tenant"]&.dup&.freeze).freeze
        end

        def valid_mode_list?(value)
          value.is_a?(Array) && !value.empty? &&
            value.all? { |element| present_text?(element) }
        end

        def present_text?(value)
          value.is_a?(String) && !value.strip.empty?
        end

        def deep_freeze(value)
          case value
          when Hash
            value.each do |key, element|
              deep_freeze(key)
              deep_freeze(element)
            end
          when Array
            value.each { |element| deep_freeze(element) }
          end
          value.freeze
        end
      end
    end
  end
end
