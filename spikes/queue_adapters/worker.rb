# frozen_string_literal: true

require_relative "boot"

# Use the backend's real supervisor/worker entrypoint, never test inline mode.
SolidQueue::Supervisor.start(
  workers: [{ queues: "default", threads: 2, processes: 1, polling_interval: 0.1 }],
  dispatchers: [{ polling_interval: 0.1, batch_size: 100 }],
  skip_recurring: true
)
