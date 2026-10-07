# frozen_string_literal: true

namespace :a2a do
  namespace :rails do
    namespace :tasks do
      desc "Delete expired a2a-rails Tasks in bounded batches"
      task prune: :environment do
        store = A2A::Rails.configuration.resolve_task_store
        unless store.respond_to?(:prune_expired)
          abort "Configured a2a-rails Task Store does not support pruning"
        end

        max_batches = Integer(ENV.fetch("A2A_TASK_PRUNE_MAX_BATCHES", "100"), 10)
        abort "A2A_TASK_PRUNE_MAX_BATCHES must be positive" unless max_batches.positive?

        total = 0
        batches = 0

        while batches < max_batches
          deleted = store.prune_expired
          break if deleted.zero?

          total += deleted
          batches += 1
        end

        stats = store.respond_to?(:maintenance_stats) ? store.maintenance_stats : {}
        remaining = stats[:expired]

        puts "a2a-rails Task prune: deleted=#{total} batches=#{batches}" +
          (remaining.nil? ? "" : " expired_remaining=#{remaining}")
      rescue ArgumentError => error
        abort error.message
      end

      desc "Print aggregate a2a-rails Task maintenance counts"
      task stats: :environment do
        store = A2A::Rails.configuration.resolve_task_store
        unless store.respond_to?(:maintenance_stats)
          abort "Configured a2a-rails Task Store does not support maintenance stats"
        end

        stats = store.maintenance_stats
        puts [
          "a2a-rails Task stats:",
          "total=#{stats.fetch(:total)}",
          "active=#{stats.fetch(:active)}",
          "terminal=#{stats.fetch(:terminal)}",
          "expired=#{stats.fetch(:expired)}"
        ].join(" ")
      end
    end
  end
end
