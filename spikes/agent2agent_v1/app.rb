# frozen_string_literal: true

require "set"
require "a2a"
require "securerandom"
require "time"
require "digest"
require "stringio"

# Disposable compatibility probe; these classes are NOT the gem's public API.
module Agent2AgentV1Spike
  class MemoryStore
    TERMINAL = %w[TASK_STATE_COMPLETED TASK_STATE_FAILED TASK_STATE_REJECTED TASK_STATE_CANCELED].freeze

    def initialize
      @tasks = {}
      @pages = {}
      @mutex = Mutex.new
    end

    def save(task)
      @mutex.synchronize { @tasks[task.fetch("id")] = copy(task) }
    end

    def fetch(id)
      @mutex.synchronize { copy(find(id)) }
    end

    def transition(id, state, artifacts: nil)
      @mutex.synchronize do
        task = find(id)
        unless TERMINAL.include?(task.dig("status", "state"))
          task["status"] = { "state" => state, "timestamp" => Time.now.utc.iso8601(6) }
          task["artifacts"] = artifacts if artifacts
        end
        copy(task)
      end
    end

    def cancel(id)
      @mutex.synchronize do
        task = find(id)
        state = task.dig("status", "state")
        raise A2A::TaskNotCancelableError.new(id, state: state) if TERMINAL.include?(state)

        task["status"] = { "state" => "TASK_STATE_CANCELED", "timestamp" => Time.now.utc.iso8601(6) }
        copy(task)
      end
    end

    # Opaque snapshot cursors keep subsequent pages stable when tasks change.
    # This disposable store does not provide persistence or cursor expiry.
    def list(params)
      size = params.fetch("pageSize", 50)
      unless size.is_a?(Integer) && (1..100).cover?(size)
        raise A2A::InvalidParamsError.new("pageSize must be an integer from 1 to 100")
      end
      fingerprint = Digest::SHA256.hexdigest(JSON.generate(params.reject { |k, _| k == "pageToken" }.sort.to_h))
      @mutex.synchronize do
        token = params["pageToken"]
        if token && !token.empty?
          cursor = @pages[token]
          unless cursor && cursor[:fingerprint] == fingerprint
            raise A2A::InvalidParamsError.new("Invalid pageToken or changed query")
          end
          rows, offset = cursor.values_at(:rows, :offset)
        else
          rows = @tasks.values.select do |task|
            (!params["contextId"] || task["contextId"] == params["contextId"]) &&
              (!params["status"] || task.dig("status", "state") == params["status"]) &&
              (!params["statusTimestampAfter"] || Time.iso8601(task.dig("status", "timestamp")) >= Time.iso8601(params["statusTimestampAfter"]))
          end
          rows = copy(rows.sort_by { |t| [t.dig("status", "timestamp"), t["id"]] }.reverse)
          offset = 0
        end
        next_offset = offset + size
        next_token = ""
        if next_offset < rows.length
          next_token = SecureRandom.uuid
          @pages[next_token] = { rows: rows, offset: next_offset, fingerprint: fingerprint }
        end
        { "tasks" => copy(rows.slice(offset, size) || []), "totalSize" => rows.length,
          "pageSize" => size, "nextPageToken" => next_token }
      end
    end

    private

    def find(id)
      @tasks[id] || raise(A2A::TaskNotFoundError.new(id))
    end

    def copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  class App
    attr_reader :store, :card, :sdk

    def initialize(handler: nil)
      @store = MemoryStore.new
      @handler = handler || ->(message:, context:) { "Echo: #{message[:parts].map { |p| p[:text] }.join("\n")}" }
      @card = {
        "name" => "Echo Agent", "description" => "SDK compatibility probe", "version" => "0.1.0-spike",
        "supportedInterfaces" => [{ "url" => "http://localhost:9292/a2a", "protocolBinding" => "JSONRPC", "protocolVersion" => "1.0" }],
        "capabilities" => { "streaming" => false, "pushNotifications" => false, "extendedAgentCard" => false },
        "defaultInputModes" => ["text/plain"], "defaultOutputModes" => ["text/plain"],
        "skills" => [{ "id" => "reply", "name" => "Reply", "description" => "Echo text", "tags" => ["echo"] }]
      }
      schema("Agent Card", @card)
      @sdk = A2A.agent(agent_card: @card) { |env| dispatch(env) }
    end

    def call(env)
      path = env["PATH_INFO"]
      if path == "/.well-known/agent-card.json"
        return http(405, "Method Not Allowed", "allow" => "GET") unless env["REQUEST_METHOD"] == "GET"
        return [200, { "content-type" => "application/json" }, [JSON.generate(@card)]]
      end
      return http(404, "Not Found") unless path == "/a2a"
      return http(405, "Method Not Allowed", "allow" => "POST") unless env["REQUEST_METHOD"] == "POST"
      return http(415, "Unsupported Media Type") unless env["CONTENT_TYPE"].to_s.split(";").first.to_s.strip == "application/json"

      # Rewrite only the internal SDK path. REST/gRPC/well-known paths never reach it.
      # Rack 3 inputs need not implement rewind; the SDK unconditionally uses it.
      sdk_env = env.merge("PATH_INFO" => "/", "rack.input" => StringIO.new(env.fetch("rack.input").read))
      status, headers, body = @sdk.call(sdk_env)
      [status, headers.merge("a2a-version" => "1.0"), body]
    end

    private

    def dispatch(env)
      request = Rack::Request.new(env)
      version = env["HTTP_A2A_VERSION"] || request.GET["A2A-Version"]
      version = "0.3" if version.nil? || version.empty?
      raise A2A::VersionNotSupportedError.new(version) unless version == "1.0"

      operation = env.fetch("a2a.operation")
      params = env.fetch("a2a.request").to_h
      begin
        env.fetch("a2a.request").valid!
      rescue A2A::Protocol::JsonSchema::ValidationError
        raise A2A::InvalidParamsError.new("Invalid request parameters")
      end
      if params["tenant"] && !params["tenant"].empty?
        raise A2A::InvalidParamsError.new("This probe has no tenant")
      end
      history = params["historyLength"]
      if history && !(history.is_a?(Integer) && history >= 0)
        raise A2A::InvalidParamsError.new("historyLength must be a nonnegative integer")
      end
      case operation
      when "SendMessage"
        schema("Send Message Response", "task" => send_message(params))
      when "GetTask"
        schema("Task", project(@store.fetch(required_id(params)), params, artifacts: true))
      when "ListTasks"
        if params["statusTimestampAfter"]
          begin
            Time.iso8601(params["statusTimestampAfter"])
          rescue ArgumentError
            raise A2A::InvalidParamsError.new("Invalid statusTimestampAfter")
          end
        end
        result = @store.list(params)
        result["tasks"] = result["tasks"].map { |t| project(t, params, artifacts: params["includeArtifacts"] == true) }
        schema("List Tasks Response", result)
      when "CancelTask"
        schema("Task", @store.cancel(required_id(params)))
      when "SendStreamingMessage", "SubscribeToTask"
        raise A2A::UnsupportedOperationError.new
      when /TaskPushNotificationConfig/
        raise A2A::PushNotificationNotSupportedError.new
      when "GetExtendedAgentCard"
        raise A2A::ExtendedAgentCardNotConfiguredError.new
      else
        raise A2A::UnsupportedOperationError.new
      end
    end

    def send_message(params)
      message = params["message"]
      unless message.is_a?(Hash) && message["messageId"].is_a?(String) && !message["messageId"].empty? &&
          message["role"] == "ROLE_USER" && message["parts"].is_a?(Array) && !message["parts"].empty?
        raise A2A::InvalidParamsError.new("messageId, ROLE_USER and nonempty parts are required")
      end
      unless message["parts"].all? { |p| p["text"].is_a?(String) && (p.keys & %w[data raw url]).empty? }
        raise A2A::ContentTypeNotSupportedError.new
      end
      if message["taskId"] && !message["taskId"].empty?
        @store.fetch(message["taskId"])
        raise A2A::UnsupportedOperationError.new(message: "Task continuation is outside this spike")
      end
      id = SecureRandom.uuid
      context_id = message["contextId"].to_s.empty? ? SecureRandom.uuid : message["contextId"]
      task = { "id" => id, "contextId" => context_id,
        "status" => { "state" => "TASK_STATE_SUBMITTED", "timestamp" => Time.now.utc.iso8601(6) },
        "history" => [message] }
      @store.save(task)
      @store.transition(id, "TASK_STATE_WORKING")
      # Explicit SDK-independent application boundary.
      output = @handler.call(message: { message_id: message["messageId"], role: :user,
        parts: message["parts"].map { |p| { text: p["text"] } } },
        context: { task_id: id, context_id: context_id, skill_id: :reply })
      artifacts = [{ "artifactId" => SecureRandom.uuid, "parts" => [{ "text" => output }] }]
      @store.transition(id, "TASK_STATE_COMPLETED", artifacts: artifacts)
    end

    def required_id(params)
      id = params["id"]
      raise A2A::InvalidParamsError.new("id is required") unless id.is_a?(String) && !id.empty?
      id
    end

    def project(task, params, artifacts:)
      task.delete("artifacts") unless artifacts
      if params.key?("historyLength")
        length = params["historyLength"]
        task["history"] = length.zero? ? [] : task.fetch("history", []).last(length)
      end
      task
    end

    def schema(name, hash)
      object = A2A::Protocol::JsonSchema[name].new(hash)
      object.valid!
      object
    end

    def http(status, message, headers = {})
      [status, { "content-type" => "text/plain" }.merge(headers), [message]]
    end
  end
end
