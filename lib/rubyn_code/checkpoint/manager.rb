# frozen_string_literal: true

require 'fileutils'

module RubynCode
  # Checkpoints let a user rewind a session, mirroring Claude Code's /rewind.
  # A checkpoint is taken at the start of each user turn and captures:
  #   - the conversation state (so chat can be rolled back), and
  #   - the original contents of every file mutated during that turn (so code
  #     can be restored).
  #
  # File contents are captured lazily by Checkpoint::Hook on :pre_tool_use,
  # just before a mutating tool runs, so only files that actually change are
  # snapshotted.
  module Checkpoint
    # Marker stored for a path that did not exist when first touched, so a
    # rewind deletes it rather than recreating empty content.
    ABSENT = :absent

    class Manager
      MAX_CHECKPOINTS = 30

      def initialize(project_root:)
        @project_root = project_root
        @checkpoints = []
        @seq = 0
        @current = nil
      end

      # Open a new checkpoint for a user turn. Captures the conversation as it
      # stands before the agent acts.
      #
      # @param label [String] short description (usually the user's message)
      # @param conversation [Agent::Conversation]
      # @return [Integer] the checkpoint id
      def checkpoint!(label:, conversation:)
        @seq += 1
        @current = {
          id: @seq,
          label: summarize(label),
          messages: Array(conversation.messages).dup,
          files: {}
        }
        @checkpoints << @current
        @checkpoints.shift while @checkpoints.size > MAX_CHECKPOINTS
        @seq
      end

      # Record a file's original contents before it is mutated (once per
      # checkpoint per path). No-op when no checkpoint is open.
      #
      # @param path [String] absolute or project-relative path
      # @return [void]
      def record_file(path)
        return unless @current && path

        abs = File.expand_path(path.to_s, @project_root)
        return if @current[:files].key?(abs)

        @current[:files][abs] = File.file?(abs) ? File.read(abs) : ABSENT
      rescue StandardError => e
        RubynCode::Debug.warn("Checkpoint capture failed for #{path}: #{e.message}")
      end

      # @return [Array<Hash>] {id:, label:, files:} newest last
      def list
        @checkpoints.map { |c| { id: c[:id], label: c[:label], files: c[:files].size } }
      end

      def empty? = @checkpoints.empty?

      def latest_id = @checkpoints.last&.fetch(:id)

      # Restore a checkpoint. Scope :both (default), :code, or :chat.
      # Checkpoints newer than the restored one are discarded.
      #
      # @return [Hash, nil] summary { id:, files_restored: } or nil if not found
      def restore(id, conversation, scope: :both)
        checkpoint = @checkpoints.find { |c| c[:id] == id }
        return nil unless checkpoint

        restored_files = restore_files(checkpoint) if %i[both code].include?(scope)
        conversation.replace!(checkpoint[:messages].dup) if %i[both chat].include?(scope)

        @checkpoints.reject! { |c| c[:id] > id }
        @current = nil
        { id: id, files_restored: restored_files || 0 }
      end

      private

      def restore_files(checkpoint)
        checkpoint[:files].each do |abs, content|
          if content == ABSENT
            FileUtils.rm_f(abs)
          else
            File.write(abs, content)
          end
        end
        checkpoint[:files].size
      end

      def summarize(label)
        text = label.to_s.tr("\n", ' ').strip
        text.length > 60 ? "#{text[0, 57]}…" : text
      end
    end
  end
end
