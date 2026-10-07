# frozen_string_literal: true

require "logger"
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "a2a-rails"
require "a2a/rails/task/active_record_store"

ADAPTER = ENV.fetch("QUEUE_ADAPTER")
raise "Unsupported smoke adapter" unless %w[solid_queue sidekiq].include?(ADAPTER)

require ADAPTER
if ADAPTER == "sidekiq"
  # The Sidekiq CLI loads Sidekiq before this minimal Rails app. Load its
  # Rails integration explicitly in both producer and worker boot paths.
  require "sidekiq/rails"
  Sidekiq.configure_client { |config| config.redis = { url: ENV.fetch("REDIS_URL") } }
  Sidekiq.configure_server { |config| config.redis = { url: ENV.fetch("REDIS_URL") } }
end

module QueueAdapterSmoke
  class Invocation < ActiveRecord::Base
    self.table_name = "smoke_invocations"
  end

  class Handler
    def self.call(message:, context:)
      Invocation.create!(task_id: context.fetch(:task_id),
        principal_id: context.fetch(:principal_id),
        idempotency_key: context.fetch(:idempotency_key))
      text = message.fetch(:parts).first.fetch(:text)
      raise "test handler failure" if text == "fail"
      raise A2A::Rails::RejectedTask, "test rejection" if text == "reject"

      "adapter result"
    end
  end

  class Agent < A2A::Rails::Agent
    name "Queue adapter test Agent"
    description "Isolated adapter compatibility smoke"
    version "1.0"
    execution_mode :async
    skill :reply, description: "Reply", tags: ["reply"], handler: Handler
  end

  class Application < Rails::Application
    config.root = ENV.fetch("SMOKE_ROOT")
    config.eager_load = false
    config.secret_key_base = "queue-adapter-smoke-secret".ljust(64, "x")
    config.logger = Logger.new($stdout)
    config.log_level = :warn
    config.active_job.queue_adapter = ADAPTER.to_sym
    config.solid_queue.use_skip_locked = false if ADAPTER == "solid_queue"
  end
end

QueueAdapterSmoke::Application.initialize!
A2A::Rails.configure do |config|
  config.agent = "QueueAdapterSmoke::Agent"
  config.task_execution_mode = :async
  config.logger = Rails.logger
end
store = A2A::Rails::Task::ActiveRecordStore.new(cursor_secret: "adapter-smoke-cursor-secret".ljust(64, "x"))
A2A::Rails.instance_variable_set(:@runtime, A2A::Rails::Runtime.new(store: store))

