# frozen_string_literal: true

require_relative "../test_helper"

class ArtifactMapperTest < Minitest::Test
  def setup
    @mapper = A2A::Rails::Task::ArtifactMapper.new(id_generator: -> { "artifact-1" })
  end

  def test_maps_string_to_text_part
    assert_equal(
      { artifact_id: "artifact-1", parts: [{ text: "hello" }] },
      @mapper.call("hello")
    )
  end

  def test_maps_hash_to_data_part_without_sharing_mutable_data
    value = { products: [{ id: 1 }] }
    artifact = @mapper.call(value)
    value[:products][0][:id] = 2

    assert_equal({ products: [{ id: 1 }] }, artifact.dig(:parts, 0, :data))
  end

  def test_maps_array_to_data_part
    assert_equal(
      { artifact_id: "artifact-1", parts: [{ data: [1, 2] }] },
      @mapper.call([1, 2])
    )
  end

  def test_nil_produces_no_artifact
    assert_nil @mapper.call(nil)
  end

  def test_unsupported_result_type_raises_explicit_error
    error = assert_raises(A2A::Rails::ArtifactMappingError) { @mapper.call(123) }

    assert_match "Integer", error.message
  end
end
