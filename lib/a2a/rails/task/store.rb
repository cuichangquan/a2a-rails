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

        def claim_execution(_task_id, principal_id: nil, **_attributes)
          raise NotImplementedError, "Task store does not implement async execution claim"
        end

        def cancel(_task_id, principal_id: nil, **_attributes)
          raise NotImplementedError, "Task stores must implement #cancel"
        end

        def list(principal_id: nil, **_filters)
          raise NotImplementedError, "Task stores must implement #list"
        end

        def prune_expired(**_options)
          raise NotImplementedError, "Task store does not implement maintenance pruning"
        end

        def maintenance_stats(**_options)
          raise NotImplementedError, "Task store does not implement maintenance stats"
        end
      end
    end
  end
end
