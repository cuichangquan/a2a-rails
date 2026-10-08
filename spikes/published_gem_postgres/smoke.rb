# frozen_string_literal: true

# Step 26-1: generates a NEW Rails app against PostgreSQL and tests the
# PUBLISHED 0.2.0.rc2 Gem. This is not a path:/git: checkout test.
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "timeout"

module PublishedGemPostgresSmoke
  module_function

  EXPECTED_SHA256 = "d65fdd65003987ece96f0a90a4cf28563929be99d26658deeb275fca30c5d694"
  PROBE = File.expand_path("probe.rb", __dir__)

  INITIALIZER = <<~'RUBY'
    A2A::Rails.configure do |config|
      config.agent = "EchoAgent"
      config.public_base_url = "https://agents.example.test"
      config.task_store = :active_record
      config.task_page_token_secret = "step-26-1-installed-gem-test-only-cursor-secret".ljust(64, "x")
      config.task_retention = 3600
      config.task_prune_batch_size = 1
      config.security_schemes = {
        "bearer" => { "httpAuthSecurityScheme" => { "scheme" => "Bearer" } }
      }
      config.security_requirements = [
        { "schemes" => { "bearer" => { "list" => [] } } }
      ]
      # Test fixtures only; this is NOT a real token signature/issuer verifier.
      config.authenticate_request = lambda do |request|
        {
          "Bearer client-a" => "tenant-A:client",
          "Bearer client-b" => "tenant-B:client"
        }[request.get_header("HTTP_AUTHORIZATION")]
      end
    end
  RUBY

  AGENT = <<~'RUBY'
    class EchoAgent < A2A::Rails::Agent
      name "Published rc2 PostgreSQL Echo Agent"
      description "Step 26-1 isolated installed-Gem smoke"
      version "1.0"

      skill :reply, description: "Reply", tags: %w[echo], handler: Echo::Reply
    end
  RUBY

  HANDLER = <<~'RUBY'
    class Echo::Reply
      def self.call(message:, context:)
        "Echo: #{message.fetch(:parts).filter_map { |part| part[:text] }.join("\n")}"
      end
    end
  RUBY

  def assert(condition, message)
    raise message unless condition
  end

  def run!(*args, chdir:, env: {})
    puts "+ #{args.join(' ')}"
    stdout, stderr, status = Open3.capture3(env, *args, chdir: chdir)
    puts stdout unless stdout.empty?
    warn stderr unless stderr.empty?
    assert(status.success?, "command failed (#{status.exitstatus}): #{args.join(' ')}")
    stdout
  end

  def runner!(host, phase, state)
    run!("bundle", "exec", "bin/rails", "runner", PROBE, chdir: host,
      env: { "A2A_SMOKE_PHASE" => phase, "A2A_SMOKE_STATE" => state })
  end

  def install_host!(root)
    host = File.join(root, "rails-host")
    rails_constraint = Gem::Requirement.new(ENV.fetch("TARGET_RAILS"))
    railties = Gem::Specification.find_all_by_name("railties")
      .select { |spec| rails_constraint.satisfied_by?(spec.version) }
      .max_by(&:version)
    assert(railties, "required Rails generator version is not installed")
    run!("rails", "_#{railties.version}_", "new", host, "--minimal", "--database=postgresql",
      "--skip-asset-pipeline", "--skip-bootsnap", "--skip-bundle", "--skip-git",
      chdir: root)
    File.write(File.join(host, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"

      gem "rails", "#{ENV.fetch('TARGET_RAILS')}"
      gem "pg", ">= 1.5", "< 3"
      gem "a2a-rails", "= 0.2.0.rc2"
    GEMFILE

    run!("bundle", "install", chdir: host)
    # Published rc2 currently needs a host inflection workaround in a real
    # production eager-load Rails app (tracked at Issue #65). This fixture
    # is NOT proof of zero-configuration production startup.
    File.write(File.join(host, "config/initializers/inflections.rb"), <<~'RUBY')
      ActiveSupport::Inflector.inflections(:en) do |inflect|
        inflect.acronym "A2A"
      end
    RUBY
    run!("bundle", "exec", "bin/rails", "generate", "a2a:rails:task_store", chdir: host)
    run!("bundle", "exec", "bin/rails", "generate", "a2a:rails:agent", "echo", chdir: host)

    migration = Dir.glob(File.join(host, "db/migrate/*create_a2a_rails_tasks.rb"))
    assert(migration.length == 1, "installed-Gem generator did not create exactly one migration")
    File.write(File.join(host, "config/initializers/a2a_rails.rb"), INITIALIZER)
    File.write(File.join(host, "app/agents/echo_agent.rb"), AGENT)
    FileUtils.mkdir_p(File.join(host, "app/services/echo"))
    File.write(File.join(host, "app/services/echo/reply.rb"), HANDLER)

    run!("bundle", "exec", "bin/rails", "db:migrate", chdir: host)
    host
  end

  def run_race!(host, state)
    root = File.dirname(state)
    children = []
    begin
      %w[completed failed].each do |target|
        output = File.join(root, "worker-#{target}.log")
        pid = Process.spawn(
          { "A2A_SMOKE_PHASE" => "race", "A2A_SMOKE_STATE" => state, "A2A_RACE_TARGET" => target },
          "bundle", "exec", "bin/rails", "runner", PROBE,
          chdir: host, out: output, err: [:child, :out]
        )
        children << [pid, output]
      end

      Timeout.timeout(90) do
        until %w[completed failed].all? { |state| File.exist?(File.join(root, "ready-#{state}")) }
          # Fail immediately when a child exits before reaching the barrier.
          children.each do |pid, output|
            result = Process.waitpid2(pid, Process::WNOHANG)
            raise "race worker exited early: #{File.read(output)}" if result
          end
          sleep 0.05
        end
        File.write(File.join(root, "race-go"), "go")
        children.each do |pid, output|
          _pid, status = Process.waitpid2(pid)
          assert(status.success?, "race worker failed: #{File.read(output)}")
          puts File.read(output)
        end
      end
    ensure
      children.each do |pid, _|
        begin
          Process.kill("KILL", pid)
          Process.wait(pid)
        rescue Errno::ESRCH, Errno::ECHILD
          # Already reaped.
        end
      end
    end
  end

  def run
    published_gem = ENV.fetch("PUBLISHED_GEM_FILE")
    assert(Digest::SHA256.file(published_gem).hexdigest == EXPECTED_SHA256,
      "published RubyGems rc2 bytes do not match approved SHA256")

    Dir.mktmpdir("a2a-rails-published-postgres-") do |root|
      host = install_host!(root)
      state = File.join(root, "ids.json")

      runner!(host, "create", state)
      runner!(host, "restart", state)
      run_race!(host, state)
      runner!(host, "expire", state)

      before = run!("bundle", "exec", "bin/rails", "a2a:rails:tasks:stats", chdir: host)
      assert(before.include?("expired=2"), "stats did not report two expired Tasks")

      first = run!("bundle", "exec", "bin/rails", "a2a:rails:tasks:prune",
        chdir: host, env: { "A2A_TASK_PRUNE_MAX_BATCHES" => "1" })
      assert(first.include?("deleted=1 batches=1 expired_remaining=1"),
        "prune did not enforce one-batch/one-row limit")

      second = run!("bundle", "exec", "bin/rails", "a2a:rails:tasks:prune", chdir: host)
      assert(second.include?("deleted=1") && second.include?("expired_remaining=0"),
        "second bounded prune did not clear remaining expired Task")

      after = run!("bundle", "exec", "bin/rails", "a2a:rails:tasks:stats", chdir: host)
      assert(after.include?("expired=0"), "post-prune stats still show expired Tasks")

      runner!(host, "final", state)
      puts "Step 26-1 published rc2 PostgreSQL Rails host: PASS"
    end
  end
end

PublishedGemPostgresSmoke.run
