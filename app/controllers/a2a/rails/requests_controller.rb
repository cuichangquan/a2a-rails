# frozen_string_literal: true

module A2A
  module Rails
    class RequestsController < ApplicationController
      # JSON-RPC reads its raw envelope; Rails model parameter wrapping is unused
      # and would eagerly parse/log malformed bodies before the SDK boundary.
      wrap_parameters false
      def create
        response.set_header("Cache-Control", "no-store")
        return unless validate_a2a_request_body
        return unless authenticate_a2a_request

        status, headers, body = A2A::Rails.runtime.call(
          env: request.env,
          request_base_url: request.base_url
        )

        self.status = status
        headers.each { |name, value| response.set_header(name, value) }
        self.response_body = body
      end

      private

      # Run before Rails Instrumentation builds its start_processing payload.
      # Host filter configuration is not mutated; only this A2A request is affected.
      def process_action(*)
        filters = Array(request.get_header("action_dispatch.parameter_filter"))
        request.set_header("action_dispatch.parameter_filter", filters + [/\Aparams\z/])
        # Earlier middleware may have memoized a filtered view. Invalidate only
        # request-local Rails filter caches, never the actual parameters/body.
        %i[@parameter_filter @filtered_env @filtered_path].each do |name|
          request.instance_variable_set(name, nil)
        end
        # Do not ask Rails to parse the RPC body for logging: its malformed-JSON
        # diagnostic can print raw_post before parameter filtering takes effect.
        # Runtime/SDK still receive the original body after request validation.
        request.instance_variable_set(:@filtered_parameters, { "params" => "[FILTERED]" })
        # This endpoint is JSON-RPC only. Rails format negotiation otherwise
        # parses body parameters again while constructing instrumentation data.
        request.set_header("action_dispatch.request.formats", [::Mime[:json]])
        super
      end

      def render_a2a_error(message, status:)
        # `render json:` negotiates Vary through parsed request parameters,
        # which can log an invalid raw body even after RequestGuard rejects it.
        self.status = status
        self.content_type = "application/json"
        self.response_body = JSON.generate(error: message)
      end

      def validate_a2a_request_body
        RequestGuard.enforce!(
          env: request.env,
          max_bytes: A2A::Rails.configuration.max_request_bytes
        )
        true
      rescue RequestGuard::PayloadTooLarge
        render_a2a_error("Payload too large", status: 413)
        false
      rescue RequestGuard::UnsupportedMediaType
        # This is an HTTP boundary rejection before JSON-RPC parsing (and
        # before authentication). Respond with no JSON body: a JSON string
        # under "error" is not a valid JSON-RPC Error object and confuses
        # protocol clients that parse an HTTP 415 response as JSON-RPC.
        head :unsupported_media_type
        false
      rescue RequestGuard::InvalidBody
        render_a2a_error("Invalid request body", status: 400)
        false
      rescue RequestGuard::InvalidConfiguration
        A2A::Rails.configuration.logger&.error("[a2a-rails] invalid request size configuration")
        render_a2a_error("Request validation unavailable", status: 500)
        false
      end

      def authenticate_a2a_request
        Authentication.authenticate!(
          request: request,
          configuration: A2A::Rails.configuration,
          rails_environment: ::Rails.env
        )
        true
      rescue Authentication::Unauthorized
        response.set_header("WWW-Authenticate", A2A::Rails.configuration.authentication_challenge)
        render_a2a_error("Unauthorized", status: :unauthorized)
        false
      rescue Authentication::Forbidden
        render_a2a_error("Forbidden", status: :forbidden)
        false
      rescue StandardError => error
        # The exception message may contain credentials supplied by host code.
        # Log the class only; never echo verifier failures into the response.
        A2A::Rails.configuration.logger&.error("[a2a-rails] authentication unavailable: #{error.class}")
        render_a2a_error("Authentication unavailable", status: :internal_server_error)
        false
      end
    end
  end
end
