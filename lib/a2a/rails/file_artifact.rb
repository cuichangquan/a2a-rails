# frozen_string_literal: true

require "base64"
require "uri"

module A2A
  module Rails
    # Explicit Handler result for a single A2A v1.0 file Artifact.
    #
    #   FileArtifact.bytes(data: File.binread(path), filename: "report.pdf", media_type: "application/pdf")
    #   FileArtifact.url(url: "https://files.example.com/report.pdf", filename: "report.pdf", media_type: "application/pdf")
    #
    # URLs are only *described* on the wire. The Gem never downloads them,
    # authorizes recipients, generates signed URLs or hosts files.
    class FileArtifact
      MAX_INLINE_BYTES = 1_048_576
      MAX_URL_BYTES = 2_048
      MAX_FILENAME_BYTES = 255
      MIME_TYPE = /\A[a-zA-Z0-9!#$&^_.+-]+\/[a-zA-Z0-9!#$&^_.+-]+\z/

      def self.bytes(data:, filename:, media_type:)
        unless data.is_a?(String) && data.bytesize <= MAX_INLINE_BYTES
          raise ArtifactMappingError, "inline file data must be a String of at most 1 MiB"
        end

        new(content_kind: :raw, content: Base64.strict_encode64(data.b),
          filename: filename, media_type: media_type)
      end

      def self.url(url:, filename:, media_type:)
        unless url.is_a?(String) && !url.empty? && url.bytesize <= MAX_URL_BYTES &&
            !url.match?(/[[:cntrl:]]/)
          raise ArtifactMappingError, "file URL must be an absolute HTTPS URL (at most 2048 bytes)"
        end

        parsed = URI.parse(url)
        unless parsed.is_a?(URI::HTTPS) && !parsed.host.to_s.empty? &&
            parsed.userinfo.nil? && parsed.fragment.nil?
          raise ArtifactMappingError, "file URL must use HTTPS without credentials or a fragment"
        end

        new(content_kind: :url, content: url.dup,
          filename: filename, media_type: media_type)
      rescue URI::InvalidURIError
        raise ArtifactMappingError, "invalid file URL"
      end

      def to_part
        {
          @content_kind => @content,
          filename: @filename,
          media_type: @media_type
        }
      end

      private

      def initialize(content_kind:, content:, filename:, media_type:)
        unless filename.is_a?(String) && !filename.empty? &&
            filename.bytesize <= MAX_FILENAME_BYTES &&
            !filename.include?("/") && !filename.include?("\\") &&
            !filename.match?(/[[:cntrl:]]/) && !%w[. ..].include?(filename)
          raise ArtifactMappingError, "filename must be a safe basename (at most 255 bytes)"
        end
        unless media_type.is_a?(String) && MIME_TYPE.match?(media_type)
          raise ArtifactMappingError, "media_type must be a valid MIME type such as application/pdf"
        end

        @content_kind = content_kind
        @content = content.freeze
        @filename = filename.dup.freeze
        @media_type = media_type.dup.freeze
        freeze
      end
    end
  end
end
