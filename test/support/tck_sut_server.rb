# frozen_string_literal: true

# Minimal Rails host for executing the pinned official A2A TCK.
# Run ONLY on loopback and in RAILS_ENV=test. Never expose the deliberately
# anonymous development/test fallback to public networks.
require "logger"
require "action_controller/railtie"
require "rackup"
require "webrick"
require_relative "../../lib/a2a-rails"

unless ENV.fetch("RAILS_ENV", "test") == "test" && ::Rails.env.test?
  abort "TCK SUT is restricted to RAILS_ENV=test; refusing to start"
end

module Step17TckSut
  class Handler
    def self.call(message:, context:)
      message.fetch(:parts).filter_map { |part| part[:text] }.join("\n").then do |text|
        "TCK echo: #{text}"
      end
    end
  end

  class EchoAgent < A2A::Rails::Agent
    name "a2a-rails TCK Echo"
    description "Local-only conformance SUT for A2A v1.0 JSON-RPC"
    version "1.0"

    skill :echo,
      description: "Echo text from a user message",
      tags: %w[test echo],
      handler: Handler
  end

  class Application < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "step17-tck-local-only-not-for-production"
    config.hosts.clear
    config.logger = Logger.new(nil)
    config.action_dispatch.show_exceptions = :none
  end
end

A2A::Rails.configure do |configuration|
  configuration.agent = "Step17TckSut::EchoAgent"
  # Force a deterministic loopback URL in the public Agent Card, so the TCK
  # never accidentally invokes an external service.
  configuration.public_base_url = "http://127.0.0.1:9999"
  configuration.logger = Logger.new($stderr)
  # Intentionally no verifier only because this process runs Rails test mode
  # on 127.0.0.1. Production/staging remain fail-closed.
end

Step17TckSut::Application.initialize!

# Test-only diagnostics: log metadata, never raw request bodies/credentials.
# Helps establish whether a TCK client and the Rails Rack adapter disagree
# about the Content-Length / rack.input contract.
module Step17InputDiagnostics
  def enforce!(env:, max_bytes:)
    super
  rescue A2A::Rails::RequestGuard::InvalidBody => error
    input = env["rack.input"]
    position = input.pos if input.respond_to?(:pos)
    warn "[tck-local] invalid Rack body: path=#{env['PATH_INFO'].inspect} " \
      "declared_bytes=#{env['CONTENT_LENGTH'].inspect} " \
      "stream_pos=#{position.inspect} input_class=#{input.class}"
    raise
  end
end
A2A::Rails::RequestGuard.singleton_class.prepend(Step17InputDiagnostics)

server = Rackup::Handler.get("webrick")
abort "WEBrick Rack handler unavailable" unless server
$stderr.puts "Step 17 TCK SUT listening on http://127.0.0.1:9999"
server.run(
  Step17TckSut::Application.instance,
  Host: "127.0.0.1",
  Port: 9999,
  Logger: WEBrick::Log.new(File::NULL, WEBrick::Log::WARN),
  AccessLog: []
)
