# frozen_string_literal: true

module A2A
  module Rails
    class RequestsController < ApplicationController
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

      def validate_a2a_request_body
        RequestGuard.enforce!(
          env: request.env,
          max_bytes: A2A::Rails.configuration.max_request_bytes
        )
        true
      rescue RequestGuard::PayloadTooLarge
        render json: { error: "Payload too large" }, status: 413
        false
      rescue RequestGuard::UnsupportedMediaType
        render json: { error: "Unsupported media type" }, status: 415
        false
      rescue RequestGuard::InvalidBody
        render json: { error: "Invalid request body" }, status: 400
        false
      rescue RequestGuard::InvalidConfiguration
        A2A::Rails.configuration.logger&.error("[a2a-rails] invalid request size configuration")
        render json: { error: "Request validation unavailable" }, status: 500
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
        render json: { error: "Unauthorized" }, status: :unauthorized
        false
      rescue Authentication::Forbidden
        render json: { error: "Forbidden" }, status: :forbidden
        false
      rescue StandardError => error
        # The exception message may contain credentials supplied by host code.
        # Log the class only; never echo verifier failures into the response.
        A2A::Rails.configuration.logger&.error("[a2a-rails] authentication unavailable: #{error.class}")
        render json: { error: "Authentication unavailable" }, status: :internal_server_error
        false
      end
    end
  end
end
