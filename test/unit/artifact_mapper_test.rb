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

  def test_maps_explicit_file_result_into_single_file_part
    file = A2A::Rails::FileArtifact.bytes(
      data: "\x00\xFF".b, filename: "report.bin", media_type: "application/octet-stream"
    )
    mapped = @mapper.call(file)

    assert_equal "artifact-1", mapped.fetch(:artifact_id)
    part = mapped.fetch(:parts).first
    assert_equal "report.bin", part.fetch(:filename)
    assert_equal "application/octet-stream", part.fetch(:media_type)
    assert_equal "AP8=", part.fetch(:raw)
    refute part.key?(:data)
    refute part.key?(:url)
  end

  def test_nil_produces_no_artifact
    assert_nil @mapper.call(nil)
  end

  def test_unsupported_result_type_raises_explicit_error
    error = assert_raises(A2A::Rails::ArtifactMappingError) { @mapper.call(123) }

    assert_match "Integer", error.message
  end
end
