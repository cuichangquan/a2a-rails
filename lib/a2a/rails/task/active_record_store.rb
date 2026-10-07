# frozen_string_literal: true

require "active_record"
require "active_support/message_verifier"
require "digest"
require "json"
require "time"
require_relative "../task"

module A2A
  module Rails
    module Task
      class ActiveRecordStore < Store
        UNSET = Object.new.freeze
        DEFAULT_PAGE_SIZE = 50
        MAX_PAGE_SIZE = 100
        CURSOR_PURPOSE = "a2a-rails/task-page".freeze

        class Record < ::ActiveRecord::Base
          self.table_name = "a2a_rails_tasks"
        end

        def initialize(cursor_secret:, clock: -> { Time.now.utc })
          unless cursor_secret.is_a?(String) && cursor_secret.bytesize >= 32
            raise ArgumentError, "cursor_secret must be at least 32 bytes"
          end

          @clock = clock
          @verifier = ActiveSupport::MessageVerifier.new(
            cursor_secret,
            digest: "SHA256",
            serializer: JSON
          )
        end

        def save(task)
          record = Record.create!(
            task_id: task.fetch(:id),
            owner_id: task[:owner_id],
            context_id: task.fetch(:context_id),
            state: normalized_state(task.dig(:status, :state)).to_s,
            status_timestamp: normalize_time(task.dig(:status, :timestamp)),
            status_message: task.dig(:status, :message),
            history: task.key?(:history) ? deep_stringify(task[:history]) : nil,
            artifacts: task.key?(:artifacts) ? deep_stringify(task[:artifacts]) : nil
          )

          deserialize(record)
        end

        def find(task_id, principal_id: nil)
          deserialize(find_record!(task_id, principal_id: principal_id))
        end

        def transition(task_id, state:, timestamp: Time.now.utc, artifacts: UNSET, message: UNSET,
          principal_id: nil)
          state = normalized_state(state)

          Record.transaction do
            record = locked_record!(task_id, principal_id: principal_id)
            return deserialize(record) if terminal_record?(record)

            attributes = {
              state: state.to_s,
              status_timestamp: normalize_time(timestamp),
              status_message: message.equal?(UNSET) ? nil : deep_stringify(message)
            }
            attributes[:artifacts] = deep_stringify(artifacts) unless artifacts.equal?(UNSET)
            record.update!(attributes)

            deserialize(record)
          end
        end

        def cancel(task_id, timestamp: Time.now.utc, principal_id: nil)
          Record.transaction do
            record = locked_record!(task_id, principal_id: principal_id)
            state = record.state.to_sym
            raise TaskNotCancelableError.new(task_id, state: state) if TERMINAL_STATES.include?(state)

            record.update!(
              state: "canceled",
              status_timestamp: normalize_time(timestamp),
              status_message: nil
            )

            deserialize(record)
          end
        end

        def list(context_id: nil, status: nil, status_timestamp_after: nil,
          page_size: DEFAULT_PAGE_SIZE, page_token: nil, principal_id: nil)
          validate_page_size!(page_size)
          unless page_token.nil? || page_token.is_a?(String)
            raise InvalidTaskQueryError, "page_token must be a String"
          end

          status = normalized_state(status) if status
          after = normalize_time(status_timestamp_after) if status_timestamp_after
          fingerprint = query_fingerprint(
            principal_id: principal_id,
            context_id: context_id,
            status: status,
            status_timestamp_after: after,
            page_size: page_size
          )

          if page_token && !page_token.empty?
            payload = decode_cursor(page_token)
            unless payload.fetch("fingerprint") == fingerprint
              raise InvalidTaskQueryError, "Invalid page_token or changed query"
            end

            snapshot_at = normalize_time(payload.fetch("snapshot_at"))
            last_timestamp = normalize_time(payload.fetch("last_timestamp"))
            last_task_id = payload.fetch("last_task_id")
            total_size = Integer(payload.fetch("total_size"))
          else
            snapshot_at = now
            last_timestamp = nil
            last_task_id = nil
            total_size = filtered_scope(
              principal_id: principal_id,
              context_id: context_id,
              status: status,
              status_timestamp_after: after,
              snapshot_at: snapshot_at
            ).count
          end

          scope = filtered_scope(
            principal_id: principal_id,
            context_id: context_id,
            status: status,
            status_timestamp_after: after,
            snapshot_at: snapshot_at
          )

          if last_timestamp
            scope = scope.where(
              "status_timestamp < :timestamp OR (status_timestamp = :timestamp AND task_id < :task_id)",
              timestamp: last_timestamp,
              task_id: last_task_id
            )
          end

          rows = scope
            .order(status_timestamp: :desc, task_id: :desc)
            .limit(page_size + 1)
            .to_a

          page = rows.first(page_size)
          next_page_token = ""

          if rows.length > page_size && page.any?
            last = page.last
            next_page_token = encode_cursor(
              "fingerprint" => fingerprint,
              "snapshot_at" => snapshot_at.iso8601(6),
              "last_timestamp" => last.status_timestamp.utc.iso8601(6),
              "last_task_id" => last.task_id,
              "total_size" => total_size
            )
          end

          {
            tasks: page.map { |record| deserialize(record) },
            total_size: total_size,
            page_size: page_size,
            next_page_token: next_page_token
          }
        rescue KeyError, ArgumentError, TypeError
          raise InvalidTaskQueryError, "Invalid page_token"
        end

        private

        def find_record!(task_id, principal_id:)
          record = Record.where(owner_id: principal_id, task_id: task_id).first
          raise TaskNotFoundError, task_id unless record

          record
        end

        def locked_record!(task_id, principal_id:)
          record = Record.lock.where(owner_id: principal_id, task_id: task_id).first
          raise TaskNotFoundError, task_id unless record

          record
        end

        def filtered_scope(principal_id:, context_id:, status:, status_timestamp_after:, snapshot_at:)
          scope = Record.where(owner_id: principal_id)
            .where("created_at <= ?", snapshot_at)

          scope = scope.where(context_id: context_id) if context_id
          scope = scope.where(state: status.to_s) if status
          scope = scope.where("status_timestamp >= ?", status_timestamp_after) if status_timestamp_after
          scope
        end

        def terminal_record?(record)
          TERMINAL_STATES.include?(record.state.to_sym)
        end

        def normalized_state(state)
          state = state.to_sym if state.respond_to?(:to_sym)
          return state if STATES.include?(state)

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

        def query_fingerprint(principal_id:, context_id:, status:, status_timestamp_after:, page_size:)
          normalized = [
            principal_id,
            context_id,
            status&.to_s,
            status_timestamp_after&.iso8601(6),
            page_size
          ]
          Digest::SHA256.hexdigest(JSON.generate(normalized))
        end

        def encode_cursor(payload)
          @verifier.generate(payload, purpose: CURSOR_PURPOSE)
        end

        def decode_cursor(token)
          value = @verifier.verify(token, purpose: CURSOR_PURPOSE)
          unless value.is_a?(Hash)
            raise InvalidTaskQueryError, "Invalid page_token"
          end

          value
        rescue ActiveSupport::MessageVerifier::InvalidSignature
          raise InvalidTaskQueryError, "Invalid page_token"
        end

        def deserialize(record)
          task = {
            id: record.task_id,
            owner_id: record.owner_id,
            context_id: record.context_id,
            status: {
              state: record.state.to_sym,
              timestamp: record.status_timestamp.utc.iso8601(6)
            }
          }

          task[:status][:message] = deep_symbolize(record.status_message) unless record.status_message.nil?
          task[:history] = deep_symbolize(record.history) unless record.history.nil?
          task[:artifacts] = deep_symbolize(record.artifacts) unless record.artifacts.nil?
          task
        end

        def deep_stringify(value)
          case value
          when Hash
            value.each_with_object({}) { |(key, nested), result| result[key.to_s] = deep_stringify(nested) }
          when Array
            value.map { |nested| deep_stringify(nested) }
          else
            value
          end
        end

        def deep_symbolize(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, nested), result|
              result[key.respond_to?(:to_sym) ? key.to_sym : key] = deep_symbolize(nested)
            end
          when Array
            value.map { |nested| deep_symbolize(nested) }
          else
            value
          end
        end

        def now
          @clock.call.utc
        end
      end
    end
  end
end
