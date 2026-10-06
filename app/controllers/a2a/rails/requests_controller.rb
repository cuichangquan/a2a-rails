# frozen_string_literal: true

module A2A
  module Rails
    class RequestsController < ApplicationController
      def create
        status, headers, body = A2A::Rails.runtime.call(
          env: request.env,
          request_base_url: request.base_url
        )

        self.status = status
        headers.each { |name, value| response.set_header(name, value) }
        self.response_body = body
      end
    end
  end
end
