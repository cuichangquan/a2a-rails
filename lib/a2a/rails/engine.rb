# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/module/delegation"
require "action_dispatch"
require "action_controller/api"
require "rails/engine"
require_relative "../../../app/controllers/a2a/rails/application_controller"
require_relative "../../../app/controllers/a2a/rails/agent_cards_controller"
require_relative "../../../app/controllers/a2a/rails/requests_controller"

module A2A
  module Rails
    class Engine < ::Rails::Engine
      isolate_namespace A2A::Rails

      # The Gem's app/controllers/a2a/... files define A2A, not A2a.
      # Override only the exact Zeitwerk basename, rather than mutating the
      # host's global ActiveSupport inflections (used by migrations).
      initializer "a2a-rails.zeitwerk_inflection" do
        ::Rails.autoloaders.each do |loader|
          loader.inflector.inflect("a2a" => "A2A")
        end
      end

      initializer "a2a-rails.mount_engine" do |app|
        # Defer this decision to route assembly, after host initializers have
        # had a chance to set config.server_enabled = false. Existing Rails
        # Server applications retain the default true behavior.
        app.routes.append do
          mount A2A::Rails::Engine => "/" if A2A::Rails.configuration.server_enabled
        end
      end
    end
  end
end
