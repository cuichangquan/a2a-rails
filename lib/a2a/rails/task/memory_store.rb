# frozen_string_literal: true

require "digest"
require "securerandom"
require "time"
require_relative "store"

module A2A
  module Rails
    module Task
      class MemoryStore < Store
        UNSET = Object.new.freeze
        DEFAULT_PAGE_SIZE = 50
        MAX_PAGE_SIZE = 100
        MAX_CACHED_PAGES = 128

        def initialize
          @tasks = {}
          @pages = {}
          @mutex = Mutex.new
        end

        def save(task)
          id = task.fetch(:id)
          @mutex.synchronize do
            @tasks[id] = copy(task)
            copy(@tasks[id])
          end
        end

        def find(task_id, principal_id: nil)
          @mutex.synchronize { copy(find!(task_id, principal_id: principal_id)) }
        end

        def claim_execution(task_id, timestamp: Time.now.utc, principal_id: nil)
          @mutex.synchronize do
            task = find!(task_id, principal_id: principal_id)
            return nil unless task.dig(:status, :state) == :submitted

            task[:status] = status_hash(:working, timestamp, UNSET)
            copy(task)
          end
        end

        def transition(task_id, state:, timestamp: Time.now.utc, artifacts: UNSET, message: UNSET,
          principal_id: nil)
          validate_state!(state)

          @mutex.synchronize do
            task = find!(task_id, principal_id: principal_id)
            return copy(task) if terminal?(task)

            task[:status] = status_hash(state, timestamp, message)
            task[:artifacts] = copy(artifacts) unless artifacts.equal?(UNSET)
            copy(task)
          end
        end

        def cancel(task_id, timestamp: Time.now.utc, principal_id: nil)
          @mutex.synchronize do
            task = find!(task_id, principal_id: principal_id)
            state = task.dig(:status, :state)
            raise TaskNotCancelableError.new(task_id, state: state) if TERMINAL_STATES.include?(state)

            task[:status] = status_hash(:canceled, timestamp, UNSET)
            copy(task)
          end
        end

        def list(context_id: nil, status: nil, status_timestamp_after: nil,
          page_size: DEFAULT_PAGE_SIZE, page_token: nil, principal_id: nil)
          validate_page_size!(page_size)
          unless page_token.nil? || page_token.is_a?(String)
            raise InvalidTaskQueryError, "page_token must be a String"
          end
          validate_state!(status) if status
          after = normalize_time(status_timestamp_after) if status_timestamp_after
          fingerprint = query_fingerprint(context_id:, status:, status_timestamp_after: after, page_size:,
            principal_id:)

          @mutex.synchronize do
            rows, offset = page_rows(page_token, fingerprint) do
              filtered_rows(context_id:, status:, status_timestamp_after: after, principal_id:)
            end

            next_offset = offset + page_size
            next_token = ""
            if next_offset < rows.length
              next_token = SecureRandom.uuid
              # Avoid unbounded growth from repeated list/pagination requests.
              # The oldest snapshot token expires once this per-process cap is reached.
              @pages.shift if @pages.size >= MAX_CACHED_PAGES
              @pages[next_token] = { rows: rows, offset: next_offset, fingerprint: fingerprint }
            end

            {
              tasks: copy(rows.slice(offset, page_size) || []),
              total_size: rows.length,
              page_size: page_size,
              next_page_token: next_token
            }
          end
        end

        private

        def find!(task_id, principal_id:)
          task = @tasks[task_id]
          # A foreign Task must appear indistinguishable from a missing one.
          raise TaskNotFoundError, task_id unless task && task[:owner_id] == principal_id

          task
        end

        def terminal?(task)
          TERMINAL_STATES.include?(task.dig(:status, :state))
        end

        def validate_state!(state)
          return if STATES.include?(state)

          raise InvalidTaskStateError, "Unknown task state: #{state.inspect}"
        end

        def validate_page_size!(page_size)
          return if page_size.is_a?(Integer) && (1..MAX_PAGE_SIZE).cover?(page_size)

          raise InvalidTaskQueryError, "page_size must be an integer from 1 to #{MAX_PAGE_SIZE}"
        end

        def normalize_time(value)
          return value.utc if value.respond_to?(:utc) && !value.is_a?(String)

          Time.iso8601(value.to_s).utc
        rescue ArgumentError
          raise InvalidTaskQueryError, "status_timestamp_after must be an ISO 8601 timestamp"
        end

        def status_hash(state, timestamp, message)
          status = { state: state, timestamp: normalize_time(timestamp).iso8601(6) }
          status[:message] = message unless message.equal?(UNSET)
          status
        end

        def page_rows(page_token, fingerprint)
          if page_token && !page_token.empty?
            cursor = @pages[page_token]
            unless cursor && cursor[:fingerprint] == fingerprint
              raise InvalidTaskQueryError, "Invalid page_token or changed query"
            end

            [cursor[:rows], cursor[:offset]]
          else
            [copy(yield), 0]
          end
        end

        def filtered_rows(context_id:, status:, status_timestamp_after:, principal_id:)
          @tasks.values
            .select do |task|
              task[:owner_id] == principal_id &&
                (!context_id || task[:context_id] == context_id) &&
                (!status || task.dig(:status, :state) == status) &&
                (!status_timestamp_after || task_time(task) >= status_timestamp_after)
            end
            .sort_by { |task| [task_time(task), task.fetch(:id)] }
            .reverse
        end

        def task_time(task)
          Time.iso8601(task.dig(:status, :timestamp))
        end

        def query_fingerprint(context_id:, status:, status_timestamp_after:, page_size:, principal_id:)
          normalized = [principal_id, context_id, status, status_timestamp_after&.iso8601(6), page_size]
          Digest::SHA256.hexdigest(Marshal.dump(normalized))
        end

        def copy(value)
          Marshal.load(Marshal.dump(value))
        end
      end
    end
  end
end
