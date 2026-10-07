# frozen_string_literal: true

module A2A
  module Rails
    class Runtime
      def initialize(store: nil)
        @store = store
      end

      def agent_card(request_base_url:)
        configuration = A2A::Rails.configuration
        agent = configuration.resolve_agent

        AgentCard::Builder.new(
          agent: agent,
          public_base_url: configuration.normalized_public_base_url,
          request_base_url: request_base_url,
          security: AgentCard::Security.new(configuration: configuration).fields
        ).call
      end

      def call(env:, request_base_url:, principal_id: nil)
        configuration = A2A::Rails.configuration
        agent = configuration.resolve_agent
        card = AgentCard::Builder.new(
          agent: agent,
          public_base_url: configuration.normalized_public_base_url,
          request_base_url: request_base_url,
          security: AgentCard::Security.new(configuration: configuration).fields
        ).call
        # The controller has already verified this Rack-scoped principal.
        # Never read identity from A2A JSON-RPC parameters or metadata.
        principal_id ||= env[Authentication::PRINCIPAL_ENV_KEY]
        lifecycle = Task::Lifecycle.new(store: task_store, logger: configuration.logger, principal_id: principal_id)
        request_handler = Protocol::RequestHandler.new(
          dispatcher: Dispatcher.new(agent: agent, configuration: configuration),
          lifecycle: lifecycle
        )
        adapter = Protocol::Agent2AgentAdapter.new(
          agent_card: card,
          request_handler: request_handler
        )

        adapter.call(env)
      end

      def task_store
        @store ||= A2A::Rails.configuration.resolve_task_store
      end
    end
  end
end
