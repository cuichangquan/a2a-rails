# frozen_string_literal: true

require "rails/generators/base"

module A2A
  module Rails
    class InstallGenerator < ::Rails::Generators::Base
      namespace "a2a:rails:install"
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb.tt", "config/initializers/a2a_rails.rb"
      end
    end
  end
end
