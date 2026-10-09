# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "timeout"
require "uri"
require_relative "outbound_policy"

module A2A
  module Rails
    class Client
      # Internal synchronous HTTPS transport used by the unreleased Client facade.
      #
      # DNS is checked immediately before each request; the selected IP is
      # pinned on Net::HTTP BEFORE the socket is opened. TLS peer and hostname
      # validation continue to use the original approved DNS hostname.
      class PinnedHttpsTransport
        class Error < A2A::Rails::Error
          attr_reader :reason

          def initialize(reason)
            @reason = reason
            super("Outbound A2A HTTP request failed: #{reason}")
          end
        end

        class RedirectBlocked < Error; end
        class ResponseTooLarge < Error; end
        class InvalidResponse < Error; end
        class DeadlineExceeded < Error; end

        class HTTPError < Error
          attr_reader :status

          def initialize(status)
            @status = status
            super(:http_error)
          end
        end

        Response = Struct.new(:status, :json, keyword_init: true)

        DEFAULT_OPEN_TIMEOUT = 3
        DEFAULT_READ_TIMEOUT = 10
        DEFAULT_TOTAL_TIMEOUT = 15
        DEFAULT_MAX_BYTES = 1_048_576
        DEFAULT_MAX_DEPTH = 48
        MAX_CREDENTIAL_BYTES = 4096

        def initialize(policy:, open_timeout: DEFAULT_OPEN_TIMEOUT,
                       read_timeout: DEFAULT_READ_TIMEOUT,
                       total_timeout: DEFAULT_TOTAL_TIMEOUT,
                       max_request_bytes: DEFAULT_MAX_BYTES,
                       max_response_bytes: DEFAULT_MAX_BYTES,
                       max_json_nesting: DEFAULT_MAX_DEPTH,
                       ca_file: nil)
          unless policy.respond_to?(:resolve!)
            raise Error, :invalid_policy
          end

          @policy = policy
          @open_timeout = positive_number!(open_timeout)
          @read_timeout = positive_number!(read_timeout)
          @total_timeout = positive_number!(total_timeout)
          @max_request_bytes = positive_integer!(max_request_bytes)
          @max_response_bytes = positive_integer!(max_response_bytes)
          @max_json_nesting = positive_integer!(max_json_nesting)
          @ca_file = ca_file
        end

        # Agent Card requests are public by default. Protected Cards require
        # their OWN callback and explicitly bound credential origin.
        def get_json(url:, authorization: nil, credential_origin: nil)
          perform(:get, url: url, authorization: authorization, credential_origin: credential_origin)
        end

        # A2A v1.0 JSON-RPC payload; preserves both Task and direct Message
        # response shapes without interpreting the protocol at this layer.
        def post_json(url:, json:, authorization: nil, credential_origin: nil)
          encoded = JSON.generate(json, max_nesting: @max_json_nesting, allow_nan: false)
          raise Error, :request_too_large if encoded.bytesize > @max_request_bytes

          perform(:post, url: url, body: encoded,
                  authorization: authorization, credential_origin: credential_origin)
        rescue JSON::GeneratorError, JSON::NestingError, TypeError
          raise Error.new(:invalid_request_json), cause: nil
        end

        private

        def perform(method, url:, body: nil, authorization: nil, credential_origin: nil)
          # Fail closed on syntax/origin/DNS before evaluating any credential.
          # OutboundPolicy also rejects mixed public/private DNS results.
          # DNS and credential callbacks count toward the same total deadline
          # as socket connection, request upload and response consumption.
          Timeout.timeout(@total_timeout) do
            target = @policy.resolve!(url)
            uri = URI.parse(target.url)
            raise Error, :invalid_target unless uri.is_a?(URI::HTTPS) &&
              target.host == uri.host && target.port == uri.port &&
              target.addresses.is_a?(Array) && !target.addresses.empty?

            header = credential_for(target, authorization, credential_origin)
            ip = target.addresses.first

            # The third argument nil is essential: ignore HTTP(S)_PROXY and
            # env proxy configuration, which could bypass the approved IP.
            http = Net::HTTP.new(target.host, target.port, nil)
            raise Error, :proxy_not_disabled if http.proxy?

            http.ipaddr = ip
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            http.verify_hostname = true
            http.ca_file = @ca_file unless @ca_file.nil?
            http.open_timeout = [@open_timeout, @total_timeout].min
            http.read_timeout = [@read_timeout, @total_timeout].min
            http.write_timeout = [@read_timeout, @total_timeout].min
            http.max_retries = 0 # Especially important for SendMessage.
            http.keep_alive_timeout = 0

            request_class = method == :get ? Net::HTTP::Get : Net::HTTP::Post
            request = request_class.new(uri.request_uri)
            request["Accept"] = "application/json"
            request["Accept-Encoding"] = "identity"
            request["A2A-Version"] = "1.0" if method == :post
            request["Content-Type"] = "application/json" if method == :post
            request["Authorization"] = header unless header.nil?
            request.body = body if method == :post

            payload = nil
            status = nil
            http.start do |connection|
              # Guard against a future Net::HTTP implementation that might
              # silently connect anywhere other than the pinned address.
              raise Error, :socket_address_mismatch unless connection.ipaddr == ip

              connection.request(request) do |response|
                status = response.code.to_i
                raise RedirectBlocked, :redirect_rejected if status.between?(300, 399)
                raise HTTPError, status unless status.between?(200, 299)

                content_type = response["Content-Type"].to_s.downcase.split(";", 2).first.strip
                unless ["application/json", "application/a2a+json"].include?(content_type)
                  raise InvalidResponse, :invalid_content_type
                end
                unless response["Content-Encoding"].to_s.strip.downcase.match?(/\A(?:|identity)\z/)
                  raise InvalidResponse, :unsupported_content_encoding
                end

                content_length = response["Content-Length"]
                if content_length
                  raise InvalidResponse, :invalid_content_length unless content_length.match?(/\A[0-9]+\z/)
                  raise ResponseTooLarge, :response_too_large if content_length.to_i > @max_response_bytes
                end

                payload = +""
                response.read_body do |chunk|
                  raise ResponseTooLarge, :response_too_large if payload.bytesize + chunk.bytesize > @max_response_bytes
                  payload << chunk
                end

                # Net::HTTP can return successfully on a prematurely closed
                # Content-Length body. A valid JSON prefix must not make that
                # truncated HTTP response look like a complete A2A reply.
                if content_length && payload.bytesize != content_length.to_i
                  raise InvalidResponse, :invalid_content_length
                end
              end
            end

            parsed = JSON.parse(payload, max_nesting: @max_json_nesting)
            Response.new(status: status, json: parsed).freeze
          end
        rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
          raise DeadlineExceeded.new(:timeout), cause: nil
        rescue JSON::ParserError, JSON::NestingError
          raise InvalidResponse.new(:invalid_json), cause: nil
        rescue OpenSSL::SSL::SSLError, IOError, SystemCallError, SocketError, EOFError,
               Net::HTTPBadResponse, Net::ProtocolError
          # Never surface remote bodies, headers, URLs, IPs or credentials,
          # including nested exception causes captured by error reporters.
          raise Error.new(:connection_failed), cause: nil
        end

        def credential_for(target, callback, origin)
          if callback.nil?
            raise Error, :unexpected_credential_origin unless origin.nil?
            return nil
          end
          unless callback.respond_to?(:call) && origin.is_a?(String) && origin == target.origin
            raise Error, :credential_origin_mismatch
          end

          value = begin
            callback.call
          rescue Timeout::Error
            # Preserve the outer total-deadline classification.
            raise
          rescue StandardError
            # Host token-provider exceptions may embed credentials. Never
            # surface them as the transport's public-facing error/cause.
            raise Error.new(:credential_failure), cause: nil
          end
          unless value.is_a?(String) && !value.empty? && value.bytesize <= MAX_CREDENTIAL_BYTES &&
              !value.match?(/[\r\n\x00-\x1f\x7f]/)
            raise Error, :invalid_credential
          end
          value
        end

        def positive_number!(value)
          return value if value.is_a?(Numeric) && value.finite? && value.positive?

          raise Error, :invalid_timeout
        end

        def positive_integer!(value)
          return value if value.is_a?(Integer) && value.positive?

          raise Error, :invalid_limit
        end
      end
    end
  end
end
