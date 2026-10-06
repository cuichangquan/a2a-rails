# frozen_string_literal: true

require "rails/engine"

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
