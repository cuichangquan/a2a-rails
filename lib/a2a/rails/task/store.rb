# frozen_string_literal: true

module A2A
  module Rails
    module Task
      class Store
        def save(_task)
          raise NotImplementedError, "Task stores must implement #save"
        end

        def find(_task_id, principal_id: nil)
          raise NotImplementedError, "Task stores must implement #find"
        end

        def transition(_task_id, state:, principal_id: nil, **_attributes)
          raise NotImplementedError, "Task stores must implement #transition"
        end

        def cancel(_task_id, principal_id: nil, **_attributes)
          raise NotImplementedError, "Task stores must implement #cancel"
        end

        def list(principal_id: nil, **_filters)
          raise NotImplementedError, "Task stores must implement #list"
        end
      end
    end
  end
end
