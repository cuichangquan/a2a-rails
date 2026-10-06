# frozen_string_literal: true

require_relative "../test_helper"

class ResultMapperTest < Minitest::Test
  def setup
    artifacts = A2A::Rails::Task::ArtifactMapper.new(id_generator: -> { "artifact-1" })
    @mapper = A2A::Rails::Task::ResultMapper.new(artifact_mapper: artifacts)
  end

  def test_completed_maps_handler_result_to_artifact
    assert_equal(
      {
        state: :completed,
        artifacts: [{ artifact_id: "artifact-1", parts: [{ text: "done" }] }]
      },
      @mapper.completed("done")
    )
  end

  def test_completed_nil_has_no_artifacts
    assert_equal({ state: :completed }, @mapper.completed(nil))
  end

  def test_rejected_exposes_explicit_business_reason
    error = A2A::Rails::RejectedTask.new("Request is not allowed")

    assert_equal(
      { state: :rejected, message: "Request is not allowed" },
      @mapper.rejected(error)
    )
  end

  def test_failed_uses_generic_message
    error = RuntimeError.new("database password leaked here")

    result = @mapper.failed(error)
    assert_equal :failed, result[:state]
    assert_equal "Task execution failed", result[:message]
    refute_includes result[:message], "password"
  end
end
