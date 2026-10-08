# frozen_string_literal: true

# Issue #65: clean-host regression using an EXACT, newly built source artifact.
# This file never publishes or fetches the historical RubyGems rc2 bytes.
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "timeout"

module CleanHostPostgresSmoke
  module_function

  PROBE = File.expand_path("../published_gem_postgres/probe.rb", __dir__)

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
      name "Installed candidate PostgreSQL Echo Agent"
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
      env: {
        "A2A_SMOKE_PHASE" => phase, "A2A_SMOKE_STATE" => state,
        "A2A_VERIFY_ENGINE_INFLECTION" => "1",
        "A2A_TEST_INFLECTION" => ENV.fetch("A2A_TEST_INFLECTION", "default")
      })
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
      gem "a2a-rails", "= #{ENV.fetch('A2A_RAILS_EXPECTED_VERSION', '0.2.0.rc2')}"
    GEMFILE

    run!("bundle", "install", chdir: host)
    run!("bundle", "exec", "ruby", "-rdigest", "-e", <<~'RUBY', chdir: host)
      require "a2a-rails"
      spec = Gem.loaded_specs.fetch("a2a-rails")
      candidate_engine = File.join(spec.full_gem_path, "lib/a2a/rails/engine.rb")
      source_engine = File.join(ENV.fetch("A2A_RAILS_SOURCE_ROOT"), "lib/a2a/rails/engine.rb")
      abort "did not install exact source-built Engine" unless
        Digest::SHA256.file(candidate_engine) == Digest::SHA256.file(source_engine)
      abort "loaded source checkout instead of installed Gem" if
        File.realpath(spec.full_gem_path).start_with?(
          File.realpath(ENV.fetch("A2A_RAILS_SOURCE_ROOT")) + File::SEPARATOR
        )
      puts "Clean host Gem matches changed Engine from source-built artifact"
    RUBY
    if ENV.fetch("A2A_TEST_INFLECTION", "default") == "acronym"
      # Simulate a preexisting host-wide acronym. The migration template
      # must honor this without changing the engine's isolated Zeitwerk rule.
      File.write(File.join(host, "config/initializers/inflections.rb"), <<~'RUBY')
        ActiveSupport::Inflector.inflections(:en) do |inflect|
          inflect.acronym "A2A"
        end
      RUBY
    end
    run!("bundle", "exec", "bin/rails", "generate", "a2a:rails:task_store", chdir: host)
    run!("bundle", "exec", "bin/rails", "generate", "a2a:rails:agent", "echo", chdir: host)

    migration = Dir.glob(File.join(host, "db/migrate/*create_a2a_rails_tasks.rb"))
    assert(migration.length == 1, "installed-Gem generator did not create exactly one migration")
    migration_source = File.read(migration.first)
    expected = ENV.fetch("A2A_TEST_INFLECTION", "default") == "acronym" ?
      "CreateA2ARailsTasks" : "CreateA2aRailsTasks"
    assert(migration_source.include?("class #{expected} <"),
      "generated migration class does not match host inflection: #{expected}")
    assert(!migration_source.include?("<%"), "unrendered ERB in migration")
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
    candidate_gem = ENV.fetch("CANDIDATE_GEM_FILE")
    expected = ENV.fetch("CANDIDATE_GEM_SHA256")
    assert(Digest::SHA256.file(candidate_gem).hexdigest == expected,
      "new exact source-built Gem SHA256 mismatch")
    assert(%w[default acronym].include?(ENV.fetch("A2A_TEST_INFLECTION", "default")),
      "invalid inflection scenario")

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
      puts "Exact installed Gem clean-host artifact / #{ENV.fetch("A2A_TEST_INFLECTION", "default")}: PASS"
    end
  end
end

CleanHostPostgresSmoke.run
