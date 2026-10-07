# frozen_string_literal: true

# Step 18 isolated, deliberately anonymous interoperability fixture.
# Run ONLY in Rails test mode on IPv4 loopback, never in public deployment.
require "logger"
require "action_controller/railtie"
require "puma"
require_relative "../../lib/a2a-rails"

unless ENV.fetch("RAILS_ENV", "test") == "test" && ::Rails.env.test?
  abort "Interop SUT only runs in RAILS_ENV=test"
end

module Step18InteropSut
  class Handler
    def self.call(message:, context:)
      text = message.fetch(:parts).filter_map { |part| part[:text] }.join("\n")
      "Interop echo: #{text}"
    end
  end

  class EchoAgent < A2A::Rails::Agent
    name "a2a-rails Interop Echo"
    description "Loopback-only JSON-RPC cross-language interoperability SUT"
    version "1.0"
    response_mode ->(message:) {
      message.fetch(:message_id).start_with?("interop-direct-") ? :message : :task
    }

    skill :echo,
      description: "Echo a caller's text",
      tags: %w[interop echo],
      handler: Handler
  end

  class Application < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "step18-local-test-only-not-for-production"
    config.hosts.clear
    config.logger = Logger.new(nil)
    config.action_dispatch.show_exceptions = :none
  end
end

A2A::Rails.configure do |configuration|
  configuration.agent = "Step18InteropSut::EchoAgent"
  configuration.public_base_url = "http://127.0.0.1:9998"
  configuration.logger = Logger.new($stderr)
  # Test-only localhost fallback. Production authentication is not changed.
end

Step18InteropSut::Application.initialize!
server = Puma::Server.new(Step18InteropSut::Application.instance)
server.add_tcp_listener("127.0.0.1", 9998)
$stderr.puts "Step 18 SUT listening on http://127.0.0.1:9998"
server.run.join
