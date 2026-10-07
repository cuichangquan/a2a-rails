# frozen_string_literal: true

require_relative "boot"
require "puma"

abort "HTTP SUT requires test environment" unless Rails.env.test? && ENV["HTTP_ASYNC_SMOKE"] == "1"
server = Puma::Server.new(QueueAdapterSmoke::Application.instance)
server.add_tcp_listener("127.0.0.1", 9997)
Signal.trap("TERM") { server.stop }
server.run.join
