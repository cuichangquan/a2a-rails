# frozen_string_literal: true

module A2A
  module Rails
    class AgentCardsController < ApplicationController
      def show
        response.set_header("A2A-Version", Protocol::Agent2AgentAdapter::PROTOCOL_VERSION)
        response.set_header("Cache-Control", "no-store")
        render json: A2A::Rails.runtime.agent_card(request_base_url: request.base_url)
      rescue A2A::Rails::ConfigurationError
        render json: { error: "Agent Card unavailable" }, status: :service_unavailable
      end
    end
  end
end
