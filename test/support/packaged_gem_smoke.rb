# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rubygems/package"
require "tmpdir"

module Step1512PackagedGemSmoke
  module_function

  ROOT = File.expand_path("../..", __dir__)
  RAILS_VERSION = ENV.fetch("PACKAGED_RAILS_VERSION", "~> 8.1.0")
  HOMEPAGE = "https://github.com/cuichangquan/a2a-rails"

  INITIALIZER_SCAFFOLD = <<~RUBY.freeze
    A2A::Rails.configure do |config|
      config.agent = "YourAgent"
      config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
    end
  RUBY

  AGENT_SCAFFOLD = <<~RUBY.freeze
    class EchoAgent < A2A::Rails::Agent
      name "Echo Agent"
      description "TODO"
      version "1.0"

      # Add at least one skill.
    end
  RUBY

  FINAL_INITIALIZER = <<~RUBY.freeze
    A2A::Rails.configure do |config|
      config.agent = "EchoAgent"
      config.public_base_url = ENV["A2A_PUBLIC_BASE_URL"]
    end
  RUBY

  FINAL_AGENT = <<~RUBY.freeze
    class EchoAgent < A2A::Rails::Agent
      name "Echo Agent"
      description "Echo messages"
      version "1.0"

      skill :reply,
        description: "Echo a message",
        tags: %w[echo],
        handler: Echo::Reply
    end
  RUBY

  HANDLER = <<~RUBY.freeze
    class Echo::Reply
      def self.call(message:, context:)
        text = message[:parts]
          .filter_map { |part| part[:text] }
          .join("\\n")

        "Echo: \#{text}"
      end
    end
  RUBY

  HTTP_VERIFY = <<~'RUBY'.freeze
    require "json"
    require "rack/mock"

    def assert(condition, message)
      raise message unless condition
    end

    request = Rack::MockRequest.new(Rails.application)

    card_response = request.get(
      "/.well-known/agent-card.json",
      "HTTP_HOST" => "localhost",
      "HTTP_A2A_VERSION" => "1.0"
    )
    assert(card_response.status == 200, "Agent Card status: #{card_response.status} #{card_response.body}")

    card = JSON.parse(card_response.body)
    assert(card.fetch("name") == "Echo Agent", "unexpected Agent Card name")
    assert(card.fetch("skills").first.fetch("id") == "reply", "unexpected Agent Card Skill")
    assert(card.fetch("supportedInterfaces").first.fetch("url").end_with?("/a2a"), "unexpected A2A URL")

    response = request.post(
      "/a2a",
      "HTTP_HOST" => "localhost",
      "CONTENT_TYPE" => "application/json",
      "HTTP_A2A_VERSION" => "1.0",
      input: JSON.generate(
        "jsonrpc" => "2.0",
        "id" => "1",
        "method" => "SendMessage",
        "params" => {
          "message" => {
            "messageId" => "msg-1",
            "role" => "ROLE_USER",
            "parts" => [{ "text" => "Hello" }]
          }
        }
      )
    )

    assert(response.status == 200, "SendMessage status: #{response.status} #{response.body}")
    task = JSON.parse(response.body).fetch("result").fetch("task")
    assert(task.dig("status", "state") == "TASK_STATE_COMPLETED", "SendMessage did not complete")
    assert(task.fetch("artifacts").first.fetch("parts").first.fetch("text") == "Echo: Hello", "unexpected Artifact text")

    puts "Packaged gem Echo HTTP verification: PASS"
  RUBY

  REQUIRED_PACKAGE_FILES = %w[
    lib/a2a-rails.rb
    lib/a2a/rails/engine.rb
    lib/generators/a2a/rails/install_generator.rb
    lib/generators/a2a/rails/agent_generator.rb
    lib/generators/a2a/rails/templates/initializer.rb.tt
    lib/generators/a2a/rails/templates/agent.rb.tt
    config/routes.rb
    README.md
    CHANGELOG.md
    LICENSE
  ].freeze

  REQUIRED_METADATA = {
    "source_code_uri" => HOMEPAGE,
    "changelog_uri" => "#{HOMEPAGE}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{HOMEPAGE}#readme",
    "bug_tracker_uri" => "#{HOMEPAGE}/issues",
    "rubygems_mfa_required" => "true"
  }.freeze

  def assert(condition, message)
    raise message unless condition
  end

  def run!(*command, chdir: ROOT, env: {})
    puts "+ #{command.join(' ')}"
    stdout, stderr, status = Open3.capture3(env, *command, chdir: chdir)
    puts stdout unless stdout.empty?
    warn stderr unless stderr.empty?
    raise "command failed (#{status.exitstatus}): #{command.join(' ')}" unless status.success?

    stdout
  end

  def build_and_verify_package(tmpdir)
    package_dir = File.join(tmpdir, "package")
    FileUtils.mkdir_p(package_dir)
    gem_path = File.join(package_dir, "a2a-rails.gem")

    run!("gem", "build", "a2a-rails.gemspec", "--output", gem_path)

    package = Gem::Package.new(gem_path)
    spec = package.spec
    assert(spec.name == "a2a-rails", "unexpected packaged gem name")
    assert(spec.version.to_s == "0.1.0", "unexpected packaged gem version: #{spec.version}")
    assert(spec.homepage == HOMEPAGE, "unexpected packaged gem homepage: #{spec.homepage}")
    assert(spec.license == "MIT", "unexpected packaged gem license: #{spec.license}")
    assert(spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.3.0")), "Ruby 3.3 must be supported")
    assert(!spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.2.9")), "Ruby 3.2 must not be supported")

    REQUIRED_METADATA.each do |key, value|
      assert(spec.metadata[key] == value, "unexpected gem metadata #{key}: #{spec.metadata[key].inspect}")
    end

    unpack_dir = File.join(tmpdir, "unpacked")
    FileUtils.mkdir_p(unpack_dir)
    package.extract_files(unpack_dir)

    REQUIRED_PACKAGE_FILES.each do |path|
      assert(File.file?(File.join(unpack_dir, path)), "packaged gem is missing #{path}")
    end

    puts "Built #{File.basename(gem_path)} SHA256=#{Digest::SHA256.file(gem_path).hexdigest}"
    [gem_path, spec.version.to_s]
  end

  def install_package!(gem_path)
    run!("gem", "install", "--no-document", gem_path)
    run!("gem", "install", "--no-document", "rails", "-v", RAILS_VERSION)
  end

  def create_clean_app(tmpdir, version)
    app_root = File.join(tmpdir, "clean_app")
    run!(
      "rails", "new", app_root,
      "--minimal", "--skip-asset-pipeline", "--skip-bundle", "--skip-git",
      chdir: tmpdir
    )

    File.write(
      File.join(app_root, "Gemfile"),
      <<~GEMFILE
        source "https://rubygems.org"

        gem "rails", "#{RAILS_VERSION}"
        gem "a2a-rails", "= #{version}"
      GEMFILE
    )

    run!("bundle", "install", "--local", chdir: app_root)

    loaded_path = run!(
      "bundle", "exec", "ruby", "-e",
      'require "a2a-rails"; print Gem.loaded_specs.fetch("a2a-rails").full_gem_path',
      chdir: app_root
    ).strip

    source_root = File.realpath(ROOT)
    installed_root = File.realpath(loaded_path)
    assert(!installed_root.start_with?(source_root + File::SEPARATOR), "clean app loaded a2a-rails from source checkout")
    assert(installed_root.include?("a2a-rails-#{version}"), "clean app did not load the installed packaged gem: #{installed_root}")

    puts "Clean app loaded packaged gem from #{installed_root}"
    app_root
  end

  def invoke_and_verify_generators(app_root)
    run!("./bin/rails", "generate", "a2a:rails:install", chdir: app_root)
    run!("./bin/rails", "generate", "a2a:rails:agent", "echo", chdir: app_root)

    initializer = File.join(app_root, "config/initializers/a2a_rails.rb")
    agent = File.join(app_root, "app/agents/echo_agent.rb")

    assert(File.read(initializer) == INITIALIZER_SCAFFOLD, "packaged install generator output changed")
    assert(File.read(agent) == AGENT_SCAFFOLD, "packaged agent generator output changed")
  end

  def prepare_echo_app(app_root)
    FileUtils.mkdir_p(File.join(app_root, "app/services/echo"))
    File.write(File.join(app_root, "app/services/echo/reply.rb"), HANDLER)
    File.write(File.join(app_root, "app/agents/echo_agent.rb"), FINAL_AGENT)
    File.write(File.join(app_root, "config/initializers/a2a_rails.rb"), FINAL_INITIALIZER)
    File.write(File.join(app_root, "tmp/verify_packaged_gem.rb"), HTTP_VERIFY)
  end

  def run
    previous_base_url = ENV.delete("A2A_PUBLIC_BASE_URL")

    Dir.mktmpdir("a2a-rails-step-15-12") do |tmpdir|
      gem_path, version = build_and_verify_package(tmpdir)
      install_package!(gem_path)
      app_root = create_clean_app(tmpdir, version)
      invoke_and_verify_generators(app_root)
      prepare_echo_app(app_root)
      run!("./bin/rails", "runner", "tmp/verify_packaged_gem.rb", chdir: app_root)
    end

    puts "Step 15-12 packaged gem smoke: PASS"
  ensure
    ENV["A2A_PUBLIC_BASE_URL"] = previous_base_url if previous_base_url
  end
end

Step1512PackagedGemSmoke.run
