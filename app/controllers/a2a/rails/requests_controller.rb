# frozen_string_literal: true

module A2A
  module Rails
    class RequestsController < ApplicationController
      def create
        response.set_header("Cache-Control", "no-store")
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
