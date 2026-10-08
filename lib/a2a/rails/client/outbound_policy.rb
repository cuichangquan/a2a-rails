# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "timeout"
require "uri"
require_relative "../errors"

module A2A
  module Rails
    class Client
      # Preflight checks for a *configured* outbound Agent Card or RPC URL.
      #
      # IMPORTANT: Resolve! alone does not prevent DNS rebinding. The future
      # transport MUST connect to one of Target#addresses while preserving
      # the validated Host/SNI, and repeat the decision for each connection.
      # Do not expose this as a production-ready HTTP Client.
      class OutboundPolicy
        class RejectedTarget < A2A::Rails::Error
          attr_reader :reason

          def initialize(reason)
            @reason = reason
            super("Outbound A2A target rejected: #{reason}")
          end
        end

        Target = Struct.new(:url, :origin, :host, :port, :addresses, keyword_init: true)

        # Conservative initial IPv4 policy. IPv6 is unsupported (fail closed)
        # until the pinned-connection transport verifies a complete address
        # classification and connection strategy for it.
        BLOCKED_IPV4 = %w[
          0.0.0.0/8
          10.0.0.0/8
          100.64.0.0/10
          127.0.0.0/8
          169.254.0.0/16
          172.16.0.0/12
          192.0.0.0/24
          192.0.2.0/24
          192.88.99.0/24
          192.168.0.0/16
          198.18.0.0/15
          198.51.100.0/24
          203.0.113.0/24
          224.0.0.0/4
          240.0.0.0/4
        ].map { |cidr| IPAddr.new(cidr) }.freeze

        HOST_LABEL = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

        # Resolver injection is for unit testing only; normal callers use
        # Resolv. The Client facade will not expose this override by default.
        def initialize(allowed_origins:, resolver: Resolv.method(:getaddresses))
          unless allowed_origins.is_a?(Array) && !allowed_origins.empty? && allowed_origins.all? { |value| value.is_a?(String) }
            raise RejectedTarget, :invalid_allowlist
          end
          unless resolver.respond_to?(:call)
            raise RejectedTarget, :invalid_resolver
          end

          @allowed_origins = allowed_origins.map { |value| checked_origin(value) }.uniq.freeze
          @resolver = resolver
        end

        # Check configured URL syntax and exact origin without resolving DNS.
        # The actual HTTP transport MUST call resolve! again at connect time.
        def validate_url!(value)
          uri = checked_uri(value)
          raise RejectedTarget, :unapproved_origin unless @allowed_origins.include?(canonical_origin(uri))

          uri
        end

        # Called for BOTH the configured Agent Card URL and each card-provided
        # supportedInterfaces[].url. The result is NOT permission to connect
        # by hostname: use Target#addresses as the connect-time allowlist.
        def resolve!(value)
          uri = checked_uri(value)
          origin = canonical_origin(uri)
          raise RejectedTarget, :unapproved_origin unless @allowed_origins.include?(origin)

          addresses = begin
            @resolver.call(uri.host)
          rescue Timeout::Error
            # The transport's total deadline must not be converted into a DNS failure.
            raise
          rescue StandardError
            raise RejectedTarget.new(:dns_failure), cause: nil
          end
          unless addresses.is_a?(Array) && !addresses.empty?
            raise RejectedTarget, :dns_failure
          end

          # If DNS returns even one private, unparseable or unsupported IP,
          # reject the entire result rather than silently selecting another.
          addresses = addresses.map do |address|
            parsed = IPAddr.new(address)
            unless parsed.ipv4? && BLOCKED_IPV4.none? { |range| range.include?(parsed) }
              raise RejectedTarget, :blocked_ip
            end
            parsed.to_s
          rescue IPAddr::InvalidAddressError, ArgumentError
            raise RejectedTarget.new(:invalid_dns_address), cause: nil
          end.uniq.freeze

          Target.new(
            url: uri.to_s.freeze,
            origin: origin.freeze,
            host: uri.host.freeze,
            port: uri.port,
            addresses: addresses
          ).freeze
        end

        private

        def checked_origin(value)
          uri = checked_uri(value)
          raise RejectedTarget, :invalid_allowlist unless uri.path.empty? || uri.path == "/"

          canonical_origin(uri)
        end

        def checked_uri(value)
          raise RejectedTarget, :invalid_url unless value.is_a?(String) && !value.empty? && value == value.strip
          uri = URI.parse(value)

          unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty? &&
              uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
            raise RejectedTarget, :invalid_url
          end

          host = uri.host.downcase
          labels = host.split(".", -1)
          unless host.ascii_only? && host.bytesize <= 253 && labels.size >= 2 &&
              labels.all? { |part| HOST_LABEL.match?(part) } &&
              labels.last.match?(/[a-z]/)
            raise RejectedTarget, :invalid_host
          end

          # DNS names only, never direct IPv4/IPv6 or unusual numeric forms.
          begin
            IPAddr.new(host)
            raise RejectedTarget, :ip_literal
          rescue IPAddr::InvalidAddressError
            # Expected for DNS names.
          end

          # Fail closed on encoded slashes, backslashes, controls or ambiguous
          # dot segments pending a more general URL canonicalization layer.
          path = uri.path
          if path.match?(/[%\\\\[:cntrl:]]/) || path.split("/").include?("..") || path.split("/").include?(".")
            raise RejectedTarget, :invalid_path
          end

          unless uri.port.between?(1, 65_535)
            raise RejectedTarget, :invalid_port
          end

          uri.host = host
          uri
        rescue URI::InvalidURIError, URI::InvalidComponentError
          raise RejectedTarget.new(:invalid_url), cause: nil
        end

        def canonical_origin(uri)
          base = "https://#{uri.host.downcase}"
          uri.port == 443 ? base : "#{base}:#{uri.port}"
        end
      end
    end
  end
end
