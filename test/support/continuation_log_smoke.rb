# frozen_string_literal: true
require "json"
require "logger"
require "stringio"
require "rack/mock"
require "action_controller/railtie"
require_relative "../../lib/a2a-rails"

module ContinuationLogSmoke
  LOG = StringIO.new
  class Handler
    def self.call(message:, context:)
      text = message.fetch(:parts).first.fetch(:text)
      return A2A::Rails::InputRequired.new("synthetic-private-question") if context.fetch(:history).length == 1
      raise "synthetic-private-handler-error" if text == "synthetic-private-answer"
      "complete"
    end
  end
  class Agent < A2A::Rails::Agent
    name "Log smoke"
    description "Safe synthetic logging test"
    version "1"
    skill :reply, description: "Reply", tags: ["test"], handler: Handler
  end
  class Application < ::Rails::Application
    config.eager_load = false
    config.secret_key_base = "test-only-log-smoke-secret"
    config.hosts.clear
    config.logger = ActiveSupport::Logger.new(LOG)
    config.log_level = :debug
    config.action_dispatch.show_exceptions = :none
  end
end
class HostLogController < ActionController::Base
  def show
    render plain: params.fetch(:visible)
  end
end

configuration = A2A::Rails::Configuration.new
configuration.agent = "ContinuationLogSmoke::Agent"
configuration.authenticate_request = ->(request) { "owner" if request.get_header("HTTP_AUTHORIZATION") == "Bearer fixture" }
configuration.security_schemes = {"bearer" => {"httpAuthSecurityScheme" => {"scheme" => "Bearer"}}}
configuration.security_requirements = [{"schemes" => {"bearer" => {"list" => []}}}]
configuration.logger = ActiveSupport::Logger.new(ContinuationLogSmoke::LOG)
A2A::Rails.instance_variable_set(:@configuration, configuration)
ContinuationLogSmoke::Application.initialize!
ContinuationLogSmoke::Application.routes.draw { get "/host-log", to: "host_log#show" }
original_filters = ContinuationLogSmoke::Application.config.filter_parameters.dup
notifications = []
subscription = ActiveSupport::Notifications.subscribe("start_processing.action_controller") do |*args|
  notifications << ActiveSupport::Notifications::Event.new(*args).payload[:params]
end
rack = Rack::MockRequest.new(ContinuationLogSmoke::Application.instance)
call = lambda do |id, text, task_id = nil, authorized = true|
  message = {"messageId" => id, "role" => "ROLE_USER", "parts" => [{"text" => text}]}
  message["taskId"] = task_id if task_id
  headers = {"CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0"}
  headers["HTTP_AUTHORIZATION"] = "Bearer fixture" if authorized
  rack.post("/a2a", headers.merge(input: JSON.generate(jsonrpc: "2.0", id: id, method: "SendMessage", params: {message: message})))
end
first = call.call("initial", "synthetic-private-original")
raise "initial failed" unless first.status == 200
waiting = JSON.parse(first.body).fetch("result").fetch("task")
raise "not waiting" unless waiting.dig("status", "state") == "TASK_STATE_INPUT_REQUIRED"
raise "missing question" unless waiting.dig("status", "message", "parts", 0, "text") == "synthetic-private-question"
denied = call.call("denied", "synthetic-private-denied-answer", waiting.fetch("id"), false)
raise "auth accepted" unless denied.status == 401
answer = call.call("answer", "synthetic-private-answer", waiting.fetch("id"))
raise "wrong result" unless JSON.parse(answer.body).dig("result", "task", "status", "state") == "TASK_STATE_FAILED"
malformed = rack.post("/a2a", "CONTENT_TYPE" => "application/json", "HTTP_A2A_VERSION" => "1.0",
  "HTTP_AUTHORIZATION" => "Bearer fixture", input: '{"jsonrpc":"2.0","params":"synthetic-private-malformed"')
raise "malformed body accepted" unless malformed.status == 400 && JSON.parse(malformed.body).fetch("error") == "Invalid request body"
host = rack.get("/host-log?visible=host-visible-value")
raise "host params changed" unless host.status == 200 && host.body == "host-visible-value"
log = ContinuationLogSmoke::LOG.string
raise "request body leaked" if log.include?("synthetic-private-")
raise "instrumentation body leaked" if JSON.generate(notifications).include?("synthetic-private-")
raise "filter marker missing" unless log.include?("[FILTERED]")
raise "host logging changed" unless log.include?("host-visible-value")
raise "host global filters changed" unless ContinuationLogSmoke::Application.config.filter_parameters == original_filters
ActiveSupport::Notifications.unsubscribe(subscription)
puts "Continuation request-local Rails log privacy: PASS"
