# frozen_string_literal: true

require "rubygems"
require_relative "../test_helper"

class LoadTest < Minitest::Test
  def test_version_is_defined
    refute_empty A2A::Rails::VERSION
    assert Gem::Version.correct?(A2A::Rails::VERSION)
  end

  def test_active_job_execution_classes_are_loaded
    assert defined?(A2A::Rails::ExecutionPlan)
    assert defined?(A2A::Rails::TaskExecutionJob)
    assert_operator A2A::Rails::TaskExecutionJob, :<, ActiveJob::Base
  end

  def test_protocol_adapter_classes_are_loaded
    assert defined?(A2A::Rails::Protocol::Adapter)
    assert defined?(A2A::Rails::Protocol::Agent2AgentAdapter)
  end
end
