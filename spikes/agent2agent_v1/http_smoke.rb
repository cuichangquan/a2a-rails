# frozen_string_literal: true

require "net/http"
require "json"
require "socket"
require "tempfile"
require "timeout"

# Start the documented standalone server and exercise the actual HTTP boundary.
socket = TCPServer.new("127.0.0.1", 0)
port = socket.addr[1]
socket.close
base = "http://127.0.0.1:#{port}"
log = Tempfile.new("a2a-spike-server")
pid = Process.spawn("bundle", "exec", "rackup", "-s", "webrick", "-o", "127.0.0.1", "-p", port.to_s,
  chdir: __dir__, out: log.path, err: log.path)

begin
  Timeout.timeout(20) do
    loop do
      begin
        response = Net::HTTP.get_response(URI("#{base}/.well-known/agent-card.json"))
        break if response.code == "200"
      rescue Errno::ECONNREFUSED
        raise "Server exited during startup" if Process.waitpid(pid, Process::WNOHANG)
      end
      sleep 0.1
    end
  end

  rpc = lambda do |method, params|
    uri = URI("#{base}/a2a")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["A2A-Version"] = "1.0"
    req.body = JSON.generate(jsonrpc: "2.0", id: 1, method: method, params: params)
    response = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 5, read_timeout: 5) { |http| http.request(req) }
    raise "HTTP #{response.code}" unless response.code == "200"
    JSON.parse(response.body)
  end
  task = rpc.call("SendMessage", { message: { messageId: "http-1", role: "ROLE_USER", parts: [{ text: "Hello" }] } }).fetch("result").fetch("task")
  raise "Echo mismatch" unless task.dig("status", "state") == "TASK_STATE_COMPLETED" && task.dig("artifacts", 0, "parts", 0, "text") == "Echo: Hello"
  raise "GetTask mismatch" unless rpc.call("GetTask", { id: task.fetch("id") }).fetch("result") == task
  raise "ListTasks mismatch" unless rpc.call("ListTasks", {}).dig("result", "totalSize") == 1
  raise "CancelTask mismatch" unless rpc.call("CancelTask", { id: task.fetch("id") }).dig("error", "code") == -32002
  puts "HTTP smoke PASS: server startup, Agent Card, Echo, GetTask, ListTasks, terminal CancelTask"
rescue StandardError
  warn File.read(log.path)
  raise
ensure
  begin
    Process.kill("TERM", pid)
    Timeout.timeout(5) { Process.waitpid(pid) }
  rescue Errno::ESRCH, Errno::ECHILD
    # The server already exited.
  rescue Timeout::Error
    Process.kill("KILL", pid)
    Process.waitpid(pid)
  end
  log.close!
end
