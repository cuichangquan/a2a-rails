# frozen_string_literal: true

require "json"
require "logger"
require "rack/mock"
require "tmpdir"
require "fileutils"
require "rails/generators"
require "action_controller/railtie"
require_relative "../../lib/a2a-rails"
require_relative "../../lib/generators/a2a/rails/install_generator"
require_relative "../../lib/generators/a2a/rails/agent_generator"

module Step1511GeneratedQuickStartSmoke
  module_function

  INITIALIZER_SCAFFOLD = <<~RUBY.freeze
    A2A::Rails.configure do |config|
      config.agent = "YourAgent"
      config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
    end
  RUBY

  AGENT_SCAFFOLD = <<~RUBY.freeze
    class EchoAgent < A2A::Rails::Agent
      name "Echo Agent"
      description "TODO"
      version "1.0"

      # Add at least one skill.
    end
  RUBY

  FINAL_INITIALIZER = <<~RUBY.freeze
    A2A::Rails.configure do |config|
      config.agent = "EchoAgent"
      config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
    end
  RUBY

  FINAL_AGENT = <<~RUBY.freeze
    class EchoAgent < A2A::Rails::Agent
      name "Echo Agent"
      description "Echo messages"
      version "1.0"

      skill :reply,
        description: "Echo a message",
        tags: %w[echo],
        handler: Echo::Reply
    end
  RUBY

  HANDLER = <<~RUBY.freeze
    class Echo::Reply
      def self.call(message:, context:)
        text = message[:parts]
          .filter_map { |part| part[:text] }
          .join("\\n")

        "Echo: \#{text}"
      end
    end
  RUBY

  def assert(condition, message)
    raise message unless condition
  end

  def invoke_generators(root)
    ::Rails::Generators.invoke(
      "a2a:rails:install",
      [],
      behavior: :invoke,
      destination_root: root
    )
    ::Rails::Generators.invoke(
      "a2a:rails:agent",
      ["echo"],
      behavior: :invoke,
      destination_root: root
    )
  end

  def verify_scaffolds(root)
    initializer = File.join(root, "config/initializers/a2a_rails.rb")
    agent = File.join(root, "app/agents/echo_agent.rb")

    assert(File.read(initializer) == INITIALIZER_SCAFFOLD, "install generator output changed")
    assert(File.read(agent) == AGENT_SCAFFOLD, "agent generator output changed")
    assert(A2A::Rails::InstallGenerator.namespace == "a2a:rails:install", "install generator namespace changed")
    assert(A2A::Rails::AgentGenerator.namespace == "a2a:rails:agent", "agent generator namespace changed")
  end

  def prepare_echo_app(root)
    FileUtils.mkdir_p(File.join(root, "app/services/echo"))
    File.write(File.join(root, "app/services/echo/reply.rb"), HANDLER)
    File.write(File.join(root, "app/agents/echo_agent.rb"), FINAL_AGENT)
    File.write(File.join(root, "config/initializers/a2a_rails.rb"), FINAL_INITIALIZER)
  end

  def build_application(root)
    application = Class.new(::Rails::Application)
    const_set(:Application, application)

    application.config.root = root
    application.config.eager_load = false
    application.config.secret_key_base = "step-15-11-secret-key-base"
    application.config.hosts.clear
    application.config.logger = Logger.new(nil)
    application.config.action_dispatch.show_exceptions = :none
    application
  end

  def request(application, method, path, body: nil, headers: {})
    Rack::MockRequest.new(application.instance).request(
      method,
      path,
      headers.merge(input: body.to_s)
    )
  end

  def verify_http_path(application)
    card_response = request(application, "GET", "/.well-known/agent-card.json")
    assert(card_response.status == 200, "Agent Card status: #{card_response.status} #{card_response.body}")
    card = JSON.parse(card_response.body)
    assert(card.fetch("name") == "Echo Agent", "unexpected Agent Card name")
    assert(card.fetch("skills").first.fetch("id") == "reply", "unexpected Agent Card Skill")
    assert(card.fetch("supportedInterfaces").first.fetch("url") == "http://example.org/a2a", "unexpected A2A URL")

    response = request(
      application,
      "POST",
      "/a2a",
      body: JSON.generate(
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "SendMessage",
        "params" => {
          "message" => {
            "messageId" => "msg-1",
            "role" => "ROLE_USER",
            "parts" => [{ "text" => "Hello" }]
          }
        }
      ),
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_A2A_VERSION" => "1.0"
      }
    )

    assert(response.status == 200, "SendMessage status: #{response.status} #{response.body}")
    task = JSON.parse(response.body).fetch("result").fetch("task")
    assert(task.dig("status", "state") == "TASK_STATE_COMPLETED", "SendMessage did not complete")
    assert(task.fetch("artifacts").first.fetch("parts").first.fetch("text") == "Echo: Hello", "unexpected Artifact text")
  end

  def run
    previous_base_url = ENV.delete("A2A_PUBLIC_BASE_URL")

    Dir.mktmpdir("a2a-rails-step-15-11") do |root|
      invoke_generators(root)
      verify_scaffolds(root)
      prepare_echo_app(root)

      application = build_application(root)
      application.initialize!
      verify_http_path(application)
    end

    puts "Step 15-11 generated Quick Start smoke: PASS"
  ensure
    ENV["A2A_PUBLIC_BASE_URL"] = previous_base_url if previous_base_url
  end
end

Step1511GeneratedQuickStartSmoke.run
