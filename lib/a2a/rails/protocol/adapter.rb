# frozen_string_literal: true

module A2A
  module Rails
    module Protocol
      class Adapter
        def call(_env)
          raise NotImplementedError, "Protocol adapters must implement #call"
        end
      end
    end
  end
end
