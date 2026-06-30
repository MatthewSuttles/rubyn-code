# frozen_string_literal: true

module RubynCode
  module LLM
    # Reads image files from disk and returns image content blocks suitable for
    # sending to the LLM as part of a user turn. Supports common raster formats
    # accepted by both Anthropic and OpenAI vision APIs.
    module ImageReader
      MAX_BYTES = 8 * 1024 * 1024

      MEDIA_TYPES = {
        '.png' => 'image/png',
        '.jpg' => 'image/jpeg',
        '.jpeg' => 'image/jpeg',
        '.gif' => 'image/gif',
        '.webp' => 'image/webp'
      }.freeze

      EXTENSIONS_REGEX = /\.(png|jpe?g|gif|webp)\z/i

      module_function

      # Build a base64 data URI of the form:
      #   "data:image/png;base64,iVBORw0KG..."
      # Returns nil for non-image paths or unreadable/oversized files.
      def data_uri(path)
        block = for_path(path)
        return nil unless block

        "data:#{block.media_type};base64,#{block.data}"
      end

      # @return [LLM::ImageBlock, nil] nil for non-image / unreadable paths
      def for_path(path)
        ext = File.extname(path)
        media = MEDIA_TYPES[ext.downcase] || MEDIA_TYPES[".#{ext.sub(/^\./, '').downcase}"]
        return nil unless media
        return nil unless File.file?(path)

        bytes = File.binread(path)
        return nil if bytes.bytesize > MAX_BYTES

        ImageBlock.new(media_type: media, data: Base64.strict_encode64(bytes))
      rescue Errno::ENOENT, Errno::EACCES, ArgumentError
        nil
      end

      def image_extension?(path)
        path.to_s.match?(EXTENSIONS_REGEX)
      end
    end
  end
end
