# frozen_string_literal: true

module A2A
  module Rails
    class AgentCardsController < ApplicationController
      def show
        response.set_header("A2A-Version", Protocol::Agent2AgentAdapter::PROTOCOL_VERSION)
        render json: A2A::Rails.runtime.agent_card(request_base_url: request.base_url)
      end
    end
  end
end
