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

      initializer "a2a-rails.mount_engine" do |app|
        app.routes.append do
          mount A2A::Rails::Engine => "/"
        end
      end
    end
  end
end
