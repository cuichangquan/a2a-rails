# frozen_string_literal: true

require "base64"
require_relative "../test_helper"

class FileArtifactTest < Minitest::Test
  FileArtifact = A2A::Rails::FileArtifact

  def test_binary_file_encodes_raw_bytes
    binary = "\x00\xFF\x80\x41".b
    file = FileArtifact.bytes(data: binary, filename: "output.txt", media_type: "text/plain")

    assert_predicate file, :frozen?
    assert_equal(
      { raw: Base64.strict_encode64(binary), filename: "output.txt", media_type: "text/plain" },
      file.to_part
    )
    assert_equal binary, Base64.strict_decode64(file.to_part.fetch(:raw))
  end

  def test_raw_file_size_limit
    file = FileArtifact.bytes(
      data: "a" * FileArtifact::MAX_INLINE_BYTES,
      filename: "big.dat", media_type: "application/octet-stream"
    )
    assert_equal FileArtifact::MAX_INLINE_BYTES,
      Base64.strict_decode64(file.to_part.fetch(:raw)).bytesize

    assert_raises(A2A::Rails::ArtifactMappingError) do
      FileArtifact.bytes(data: "a" * (FileArtifact::MAX_INLINE_BYTES + 1),
        filename: "oversized.dat", media_type: "application/octet-stream")
    end
  end

  def test_https_url_file_only_references_existing_remote_resource
    file = FileArtifact.url(
      url: "https://example.test/exports/output.txt?signature=test-only",
      filename: "output.txt", media_type: "text/plain"
    )

    assert_equal({
      url: "https://example.test/exports/output.txt?signature=test-only",
      filename: "output.txt", media_type: "text/plain"
    }, file.to_part)
  end

  def test_input_mutations_cannot_change_file_output
    data = "original"
    filename = "report.txt"
    media_type = "text/plain"
    url = "https://files.example.test/file"
    raw = FileArtifact.bytes(data: data, filename: filename, media_type: media_type)
    linked = FileArtifact.url(url: url, filename: filename, media_type: media_type)

    data.replace("changed")
    filename.replace("bad.txt")
    media_type.replace("text/html")
    url.replace("https://attacker.example/")

    assert_equal "b3JpZ2luYWw=", raw.to_part.fetch(:raw)
    assert_equal "report.txt", raw.to_part.fetch(:filename)
    assert_equal "text/plain", linked.to_part.fetch(:media_type)
    assert_equal "https://files.example.test/file", linked.to_part.fetch(:url)
  end

  def test_rejects_insecure_file_urls
    [
      "http://example.test/file",
      "file:///etc/passwd",
      "https://user:secret@example.test/file",
      "https://example.test/file#private",
      "//example.test/file",
      "https://example.test/\r\nInjected",
      "https://",
      "ftp://example.test/file"
    ].each do |url|
      assert_raises(A2A::Rails::ArtifactMappingError, url.inspect) do
        FileArtifact.url(url: url, filename: "output.txt", media_type: "text/plain")
      end
    end
  end

  def test_rejects_invalid_content_and_metadata
    [nil, 123, {}, "a" * (FileArtifact::MAX_INLINE_BYTES + 1)].each do |data|
      assert_raises(A2A::Rails::ArtifactMappingError) do
        FileArtifact.bytes(data: data, filename: "a.bin", media_type: "application/octet-stream")
      end
    end

    ["", ".", "..", "/tmp/a.txt", "..\\secrets.txt", "has\nnewline.txt", "x" * 256].each do |name|
      assert_raises(A2A::Rails::ArtifactMappingError, name.inspect) do
        FileArtifact.bytes(data: "ok", filename: name, media_type: "text/plain")
      end
    end

    ["", "plain", "text/plain\nHeader", nil, 42].each do |mime_type|
      assert_raises(A2A::Rails::ArtifactMappingError, mime_type.inspect) do
        FileArtifact.bytes(data: "ok", filename: "x.txt", media_type: mime_type)
      end
    end
  end
end
