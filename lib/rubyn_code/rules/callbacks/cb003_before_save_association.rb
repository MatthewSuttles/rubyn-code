# frozen_string_literal: true

module RubynCode
  module Rules
    module Callbacks
      # CB003 — before_save Mutating Non-Persisted Association
      #
      # Detects before_save callbacks that modify associated records which
      # may not yet be persisted. When a before_save callback builds or
      # mutates an association, the associated record might not have been
      # saved to the database yet. This leads to subtle data integrity
      # bugs: foreign keys may be nil, inverse associations inconsistent,
      # or the associated record silently lost if the parent transaction
      # rolls back.
      #
      # Positive examples (should flag):
      #   before_save { build_profile(name: "default") }
      #   before_save :create_default_address
      #   before_save { comments.build(body: "auto") }
      #   before_save { self.profile = Profile.new(bio: "...") }
      #   before_save { tags << Tag.new(name: "draft") }
      #   before_save { association.update!(status: "synced") }
      #
      # Negative examples (safe):
      #   after_commit :create_default_profile
      #   before_save :normalize_name          # local attribute only
      #   before_save { self.slug = name.parameterize }
      class Cb003BeforeSaveAssociation < Base
        ID = "CB003"
        CATEGORY = :callbacks
        SEVERITY = :medium
        RAILS_VERSIONS = [">= 5.0"].freeze
        CONFIDENCE_FLOOR = 0.75

        # Patterns that indicate association mutation inside a callback body.
        ASSOCIATION_MUTATION_PATTERNS = [
          # Building associations
          /\.build\b/,
          /\.build_\w+/,
          /build_\w+\(/,
          /\.create\b/,
          /\.create!\b/,

          # Assigning new unsaved records
          /\.\w+\s*=\s*\w+\.new\b/,
          /self\.\w+\s*=\s*\w+\.new\b/,

          # Collection mutation via << or push
          /\w+\s*<<\s*\w+\.new\b/,
          /\.push\(\s*\w+\.new\b/,

          # Updating/saving associated records (word.update, word.update!)
          /\w+\.update\b/,
          /\w+\.update!/,
          /\w+\.save\b/,
          /\w+\.save!/,

          # Destroying associations
          /\w+\.destroy\b/,
          /\w+\.destroy!/,
          /\w+\.delete\b/
        ].freeze

        # Method name fragments that imply association mutation when used
        # as before_save callback method names.
        ASSOCIATION_METHOD_NAMES = [
          /create_default_/i,
          /create_\w+/i,
          /build_default_/i,
          /build_\w+/i,
          /assign_\w+_record/i,
          /initialize_\w+/i,
          /setup_\w+_association/i,
          /sync_\w+/i,
          /update_\w+_record/i,
          /ensure_\w+_exists/i
        ].freeze

        class << self
          # Applies to changed Ruby model files that contain callbacks.
          #
          # @param diff_data [Hash] must contain :changed_files array
          # @return [Boolean]
          def applies_to?(diff_data)
            changed_files = diff_data.fetch(:changed_files, [])
            changed_files.any? { |f| model_file?(f) }
          end

          # Returns the prompt module text for LLM-based evaluation.
          #
          # @return [String]
          def prompt_module
            <<~PROMPT
              ## Rule CB003 — before_save Mutating Non-Persisted Association

              **Severity:** medium
              **Category:** callbacks

              ### What to look for

              Detect `before_save` callbacks in Rails models that build, create,
              assign, or otherwise mutate associated records. These operations are
              dangerous inside `before_save` because:

              1. The parent record has not yet been committed — its `id` may be nil
                 on create, so foreign keys on the association are not set correctly.
              2. If the parent save fails validation or the transaction rolls back,
                 the associated record may already have been persisted (if using
                 `create`/`create!`), creating orphaned data.
              3. Using `build` inside `before_save` can lead to infinite save loops
                 when autosave is enabled on the association.

              Flag the callback if:
              1. The inline block calls `.build`, `.create`, `.create!`, or assigns
                 `SomeModel.new` to an association.
              2. The inline block pushes a new record into a collection via `<<`.
              3. The inline block calls `.update`, `.update!`, `.save`, or `.save!`
                 on an associated record.
              4. The referenced method name implies association creation
                 (e.g. `create_default_*`, `build_*`, `ensure_*_exists`).
              5. The method body (if visible in the diff) contains any of the above
                 patterns.

              ### What is acceptable

              - `before_save` callbacks that only modify attributes on `self`
                (e.g. `self.slug = name.parameterize`).
              - `before_save` callbacks that read associations without modifying them.
              - `after_commit` or `after_save` callbacks that create associations
                (different timing concerns; covered by CB001).
              - `before_validation` callbacks that set defaults on `self`.

              ### Suggested fix

              Move association-mutating logic to `after_commit` or `after_create`
              where the parent record is guaranteed to be persisted. Alternatively,
              use `accepts_nested_attributes_for` to let Rails handle the
              association lifecycle correctly.

              ### Output format

              For each finding, report:
              - file path and line number
              - the offending code snippet
              - which sub-pattern was matched
              - suggested fix
            PROMPT
          end

          # Validates a finding by confirming the flagged line contains a
          # before_save with an association-mutation indicator.
          #
          # @param finding  [Hash] :line_content, :line_number, :file_path
          # @param diff_data [Hash] :changed_files, :file_contents
          # @return [Boolean]
          def validate(finding, diff_data)
            line_content = finding.fetch(:line_content, "")
            file_path = finding.fetch(:file_path, "")

            return false unless model_file?(file_path)
            return false unless before_save_declaration?(line_content)

            # Check inline block for association mutation
            return true if inline_association_mutation?(line_content)

            # Check if the callback method name implies association mutation
            method_name = extract_callback_method(line_content)
            return true if method_name && association_method_name?(method_name)

            # Check if the method body is available in the diff
            if method_name
              file_contents = diff_data.fetch(:file_contents, {})
              body = file_contents.fetch(file_path, "")
              return true if method_body_has_association_mutation?(body, method_name)
            end

            false
          end

          private

          # @param path [String]
          # @return [Boolean]
          def model_file?(path)
            path.match?(%r{app/models/.*\.rb\z})
          end

          # @param line [String]
          # @return [Boolean]
          def before_save_declaration?(line)
            line.match?(/\bbefore_save\b/)
          end

          # Checks if an inline block on the before_save line contains an
          # association-mutation pattern.
          #
          # @param line [String]
          # @return [Boolean]
          def inline_association_mutation?(line)
            ASSOCIATION_MUTATION_PATTERNS.any? { |pattern| line.match?(pattern) }
          end

          # Extracts the symbol method name from a before_save declaration.
          # e.g. "before_save :create_default_profile" => "create_default_profile"
          #
          # @param line [String]
          # @return [String, nil]
          def extract_callback_method(line)
            match = line.match(/\bbefore_save\s+:(\w+)/)
            match&.[](1)
          end

          # Checks if the method name itself suggests association mutation.
          #
          # @param method_name [String]
          # @return [Boolean]
          def association_method_name?(method_name)
            ASSOCIATION_METHOD_NAMES.any? { |pattern| method_name.match?(pattern) }
          end

          # Scans the file body for the method definition and checks its
          # contents for association-mutation patterns.
          #
          # @param body [String]
          # @param method_name [String]
          # @return [Boolean]
          def method_body_has_association_mutation?(body, method_name)
            return false if body.empty?

            method_regex = /def\s+#{Regexp.escape(method_name)}\b(.*?)(?=\n\s*(?:def\s|\z|end\b))/m
            match = body.match(method_regex)
            return false unless match

            method_body = match[1]
            ASSOCIATION_MUTATION_PATTERNS.any? { |pattern| method_body.match?(pattern) }
          end
        end
      end
    end
  end
end

RubynCode::Rules::Registry.register(RubynCode::Rules::Callbacks::Cb003BeforeSaveAssociation)
