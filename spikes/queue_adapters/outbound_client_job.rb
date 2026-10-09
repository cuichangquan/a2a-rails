# frozen_string_literal: true

# Step 29-5o TEST-ONLY separately executing outbound Rails Client Job.
# Loaded in the producer/worker Rails boot only when OUTBOUND_CLIENT_SMOKE=1.
# Never pass a Client, secret, callback or raw Message through the queue.
require "json"

module QueueAdapterSmoke
  class OutboundCall < ActiveRecord::Base
    self.table_name = "smoke_outbound_calls"
  end

  class OutboundLoopbackPolicy < A2A::Rails::Client::OutboundPolicy
    def resolve!(url)
      # Retain URL syntax / exact HTTPS-origin approval. Only the DNS result
      # is test-injected because a local official-public-DNS policy must deny
      # private loopback addresses.
      uri = validate_url!(url)
      Target.new(
        url: uri.to_s.freeze,
        host: uri.host.freeze,
        port: uri.port,
        origin: "https://#{uri.host}:#{uri.port}".freeze,
        addresses: ["127.0.0.1".freeze].freeze
      ).freeze
    end
  end

  class OutboundClientJob < ActiveJob::Base
    queue_as :default

    def perform(reference_id)
      # This file is just a *test* credential store shared by the producer
      # and worker process. Neither its data nor full RPC bodies are job args.
      manifest = JSON.parse(File.read(File.join(ENV.fetch("SMOKE_ROOT"), "outbound-manifest.json")))
      entry = manifest.fetch(reference_id)
      origin = entry.fetch("origin")
      token = entry.fetch("token")
      mode = entry.fetch("mode")
      policy = OutboundLoopbackPolicy.new(allowed_origins: [origin])
      transport = A2A::Rails::Client::PinnedHttpsTransport.new(
        policy: policy,
        ca_file: File.join(ENV.fetch("SMOKE_ROOT"), "outbound-test-ca.pem"),
        open_timeout: 2, read_timeout: 0.15, total_timeout: 0.45
      )
      client = A2A::Rails::Client.new(
        agent_card_url: "#{origin}/.well-known/agent-card.json",
        allowed_origins: [origin],
        authorization: -> { "Bearer #{token}" },
        credential_origin: mode == "wrong_origin" ? "https://unauthorized-agent.test" : origin,
        open_timeout: 2, read_timeout: 0.15, total_timeout: 0.45
      )
      client.instance_variable_set(
        :@resolver,
        A2A::Rails::Client::AgentCardResolver.new(
          agent_card_url: "#{origin}/.well-known/agent-card.json",
          policy: policy, transport: transport,
          authorization: -> { "Bearer #{token}" },
          credential_origin: mode == "wrong_origin" ? "https://unauthorized-agent.test" : origin
        )
      )

      result = client.send_message(
        message: {
          message_id: "message-#{reference_id}", role: "ROLE_USER",
          parts: [{ text: "private-message-Part-#{reference_id}" }]
        }
      )
      raise "Unexpected outbound SDK response" unless result.kind == :message

      OutboundCall.create!(
        reference_id: reference_id,
        worker_pid: Process.pid,
        outcome: "completed",
        reason: nil,
        remote_message_id: result.message.fetch(:message_id)
      )
    rescue A2A::Rails::Client::TimeoutError => error
      # Remote SendMessage could already have executed. Never automatically
      # retry; persist an uncertain outcome for explicit host reconciliation.
      raise "side-effecting timeout was not marked ambiguous" unless error.may_have_executed

      OutboundCall.create!(
        reference_id: reference_id, worker_pid: Process.pid,
        outcome: "uncertain_no_retry", reason: error.reason.to_s
      )
    rescue A2A::Rails::Client::TransportError => error
      raise unless mode == "wrong_origin" && error.reason == :credential_origin_mismatch

      OutboundCall.create!(
        reference_id: reference_id, worker_pid: Process.pid,
        outcome: "denied_before_rpc", reason: error.reason.to_s
      )
    end
  end
end
