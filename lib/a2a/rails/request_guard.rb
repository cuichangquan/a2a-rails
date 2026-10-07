# frozen_string_literal: true

require "stringio"

module A2A
  module Rails
    # Enforces a bounded JSON-RPC request body before application callbacks
    # or the upstream SDK can read/parse arbitrary request data.
    module RequestGuard
      DEFAULT_MAX_BYTES = 1_048_576
      MAX_CONFIGURABLE_BYTES = 16 * 1_048_576

      class PayloadTooLarge < StandardError; end
      class UnsupportedMediaType < StandardError; end
      class InvalidBody < StandardError; end
      class InvalidConfiguration < StandardError; end

      module_function

      def enforce!(env:, max_bytes:)
        unless max_bytes.is_a?(Integer) && max_bytes.between?(1, MAX_CONFIGURABLE_BYTES)
          raise InvalidConfiguration, "max_request_bytes must be between 1 and #{MAX_CONFIGURABLE_BYTES}"
        end

        media_type = env["CONTENT_TYPE"].to_s.split(";", 2).first.strip.downcase
        raise UnsupportedMediaType unless media_type == "application/json"

        encoding = env["HTTP_CONTENT_ENCODING"].to_s.strip.downcase
        raise UnsupportedMediaType unless encoding.empty? || encoding == "identity"

        length = env["CONTENT_LENGTH"]
        if length && (!length.is_a?(String) || !length.match?(/\A[0-9]+\z/))
          raise InvalidBody
        end
        raise PayloadTooLarge if length && length.to_i > max_bytes

        input = env["rack.input"]
        raise InvalidBody unless input.respond_to?(:read)

        # Read one byte beyond the permitted maximum to catch requests without
        # Content-Length, chunked bodies, and falsely understated lengths.
        body = input.read(max_bytes + 1)
        raise InvalidBody unless body.is_a?(String)
        raise PayloadTooLarge if body.bytesize > max_bytes
        raise InvalidBody if length && length.to_i != body.bytesize

        # The SDK receives the *bounded* copy, never the original input stream.
        env["rack.input"] = StringIO.new(body)
        env["CONTENT_LENGTH"] = body.bytesize.to_s
        true
      end
    end
  end
end
