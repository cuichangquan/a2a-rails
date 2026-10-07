# frozen_string_literal: true

require "digest"
require "uri"

module A2A
  module Rails
    class Configuration
      TASK_STORE_METHODS = %i[save find transition cancel list].freeze
      TASK_EXECUTION_MODES = %i[sync async].freeze
      DEFAULT_TASK_RETENTION_SECONDS = 30 * 24 * 60 * 60
      DEFAULT_TASK_PRUNE_BATCH_SIZE = 1_000
      DEFAULT_MAX_TASKS_PER_OWNER = 10_000
      DEFAULT_MAX_TASK_HISTORY_ENTRIES = 100
      DEFAULT_MAX_TASK_ARTIFACTS = 50

      attr_accessor :agent, :public_base_url, :authenticate_request, :authentication_challenge,
        :max_request_bytes, :security_schemes, :security_requirements,
        :task_store, :task_page_token_secret, :task_retention,
        :task_prune_batch_size, :max_tasks_per_owner,
        :max_task_history_entries, :max_task_artifacts,
        :task_execution_mode

      def initialize
        @agent = nil
        @public_base_url = nil
        @authenticate_request = nil
        @authentication_challenge = 'Bearer realm="a2a"'
        @security_schemes = nil
        @security_requirements = nil
        @max_request_bytes = RequestGuard::DEFAULT_MAX_BYTES
        @task_store = :memory
        @task_page_token_secret = nil
        @task_retention = DEFAULT_TASK_RETENTION_SECONDS
        @task_prune_batch_size = DEFAULT_TASK_PRUNE_BATCH_SIZE
        @max_tasks_per_owner = DEFAULT_MAX_TASKS_PER_OWNER
        @max_task_history_entries = DEFAULT_MAX_TASK_HISTORY_ENTRIES
        @max_task_artifacts = DEFAULT_MAX_TASK_ARTIFACTS
        @task_execution_mode = :sync
        @logger_set = false
      end

      def logger
        return @logger if @logger_set
        return ::Rails.logger if defined?(::Rails) && ::Rails.respond_to?(:logger)

        nil
      end

      def logger=(value)
        @logger_set = true
        @logger = value
      end

      def validate!
        validate_agent_name!
        normalized_public_base_url
        validate_task_execution_mode!(@task_execution_mode, "config.task_execution_mode")
        self
      end

      def resolve_task_execution_mode(agent:, skill:)
        mode = skill.execution_mode || agent.execution_mode || @task_execution_mode
        validate_task_execution_mode!(mode, "task execution mode")
        mode
      end

      def resolve_agent
        validate_agent_name!

        resolved = constantize(@agent.strip)
        unless resolved.is_a?(Class) && resolved <= A2A::Rails::Agent
          raise ConfigurationError, "Configured agent must inherit from A2A::Rails::Agent"
        end

        resolved.validate!
        resolved
      rescue NameError
        raise ConfigurationError, "Configured agent could not be resolved"
      end

      def normalized_public_base_url
        value = @public_base_url
        return nil if value.nil? || value.to_s.strip.empty?

        normalize_base_url(value.to_s)
      end

      def resolve_task_store
        case @task_store
        when nil, :memory
          Task::MemoryStore.new
        when :active_record
          resolve_active_record_store
        else
          validate_task_store!(@task_store)
        end
      end

      private

      def validate_task_execution_mode!(mode, label)
        return if TASK_EXECUTION_MODES.include?(mode)

        raise ConfigurationError, "#{label} must be :sync or :async"
      end

      def resolve_active_record_store
        require_relative "task/active_record_store"

        Task::ActiveRecordStore.new(
          cursor_secret: task_cursor_secret,
          retention: @task_retention,
          prune_batch_size: @task_prune_batch_size,
          max_tasks_per_owner: @max_tasks_per_owner,
          max_history_entries: @max_task_history_entries,
          max_artifacts: @max_task_artifacts
        )
      rescue LoadError => error
        raise ConfigurationError,
          "config.task_store = :active_record requires ActiveRecord in the host application (#{error.path})"
      end

      def task_cursor_secret
        configured = @task_page_token_secret
        if configured
          unless configured.is_a?(String) && configured.bytesize >= 32
            raise ConfigurationError, "config.task_page_token_secret must be at least 32 bytes"
          end
          return configured
        end

        if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
          secret = ::Rails.application.secret_key_base.to_s
          return Digest::SHA256.digest("a2a-rails/task-page-token/#{secret}") unless secret.empty?
        end

        raise ConfigurationError,
          "ActiveRecord Task Store needs Rails.application.secret_key_base or config.task_page_token_secret"
      end

      def validate_task_store!(store)
        missing = TASK_STORE_METHODS.reject { |method_name| store.respond_to?(method_name) }
        unless missing.empty?
          raise ConfigurationError, "config.task_store is missing methods: #{missing.join(", ")}"
        end

        store
      end

      def validate_agent_name!
        unless @agent.is_a?(String) && !@agent.strip.empty?
          raise ConfigurationError, "config.agent must be a non-empty class-name String"
        end

        parts = @agent.strip.sub(/\A::/, "").split("::")
        unless parts.all? { |part| part.match?(/\A[A-Z]\w*\z/) }
          raise ConfigurationError, "config.agent must be a valid class-name String"
        end
      end

      def constantize(name)
        name.sub(/\A::/, "").split("::").reduce(Object) do |namespace, constant_name|
          namespace.const_get(constant_name, false)
        end
      end

      def normalize_base_url(value)
        uri = URI.parse(value.strip)
        unless %w[http https].include?(uri.scheme) && uri.host && !uri.host.empty?
          raise ConfigurationError, "config.public_base_url must be an absolute HTTP(S) URL"
        end

        if uri.userinfo || uri.query || uri.fragment
          raise ConfigurationError, "config.public_base_url must not contain userinfo, query, or fragment"
        end

        segments = uri.path.to_s.split("/").reject(&:empty?)
        if segments.include?("a2a")
          raise ConfigurationError, "config.public_base_url must not contain /a2a"
        end

        uri.path = uri.path.to_s.sub(%r{/+\z}, "")
        uri.to_s.sub(%r{/+\z}, "")
      rescue URI::InvalidURIError
        raise ConfigurationError, "config.public_base_url must be an absolute HTTP(S) URL"
      end
    end
  end
end
