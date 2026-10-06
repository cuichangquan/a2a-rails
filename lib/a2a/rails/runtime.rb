# frozen_string_literal: true

module A2A
  module Rails
    class Runtime
      def initialize(store: Task::MemoryStore.new)
        @store = store
      end

      def agent_card(request_base_url:)
        configuration = A2A::Rails.configuration
        agent = configuration.resolve_agent

        AgentCard::Builder.new(
          agent: agent,
          public_base_url: configuration.normalized_public_base_url,
          request_base_url: request_base_url
        ).call
      end

      def call(env:, request_base_url:)
        configuration = A2A::Rails.configuration
        agent = configuration.resolve_agent
        card = AgentCard::Builder.new(
          agent: agent,
          public_base_url: configuration.normalized_public_base_url,
          request_base_url: request_base_url
        ).call
        lifecycle = Task::Lifecycle.new(store: @store, logger: configuration.logger)
        request_handler = Protocol::RequestHandler.new(
          dispatcher: Dispatcher.new(agent: agent),
          lifecycle: lifecycle
        )
        adapter = Protocol::Agent2AgentAdapter.new(
          agent_card: card,
          request_handler: request_handler
        )

        adapter.call(env)
      end
    end
  end
end
