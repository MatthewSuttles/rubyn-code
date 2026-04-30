# frozen_string_literal: true

require_relative '../../skills/pack_context'

module RubynCode
  module IDE
    module Handlers
      # Handles the "review" JSON-RPC request.
      #
      # Delegates to the existing ReviewPr tool, running it in a
      # background thread. Emits review/finding notifications as
      # findings are extracted from the review output.
      class ReviewHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          base_branch = params['baseBranch'] || 'main'
          focus       = params['focus'] || 'all'
          session_id  = params['sessionId'] || SecureRandom.uuid

          Thread.new do
            run_review(session_id, base_branch, focus)
          end

          { 'accepted' => true, 'sessionId' => session_id }
        end

        # Extract structured findings from the raw review text.
        # Looks for severity markers like [critical], [warning], etc.
        SEVERITY_PATTERN = /\[(critical|warning|suggestion|nitpick)\]/i

        private

        def run_review(session_id, base_branch, focus) # rubocop:disable Metrics/MethodLength -- review lifecycle with finding notifications
          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'reviewing'
                         })

          workspace = @server.workspace_path || Dir.pwd
          pack_context = build_pack_context(workspace)
          review_tool = Tools::ReviewPr.new(project_root: workspace)
          result = review_tool.execute(base_branch: base_branch, focus: focus, pack_context: pack_context)

          # Parse the review output into individual findings and emit them
          findings = extract_findings(result)
          findings.each_with_index do |finding, idx|
            @server.notify('review/finding', {
                             'sessionId' => session_id,
                             'index' => idx,
                             'severity' => finding[:severity],
                             'message' => finding[:message],
                             'file' => finding[:file],
                             'line' => finding[:line]
                           })
          end

          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'done',
                           'summary' => "Review complete: #{findings.size} finding(s)"
                         })
        rescue StandardError => e
          warn "[ReviewHandler] error: #{e.message}"
          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'error',
                           'error' => e.message
                         })
        end

        # Fetch skill pack context for gems detected in the repo's Gemfile.
        # Returns nil on any failure — pack context is best-effort and must never
        # block the review from running.
        #
        # @param workspace [String] absolute path to the repository
        # @return [String, nil] formatted context block or nil
        def build_pack_context(workspace)
          context = Skills::PackContext.for_repo(project_root: workspace)
          block = context.build_context_block
          block.empty? ? nil : block
        rescue StandardError
          nil
        end

        def extract_findings(review_text)
          return [] unless review_text.is_a?(String)

          findings = []
          current_finding = nil

          review_text.each_line do |line|
            if (match = line.match(SEVERITY_PATTERN))
              # Save previous finding
              findings << current_finding if current_finding

              current_finding = {
                severity: match[1].downcase,
                message: line.strip,
                file: extract_file_reference(line),
                line: extract_line_number(line)
              }
            elsif current_finding
              # Append continuation lines to the current finding
              current_finding[:message] = "#{current_finding[:message]}\n#{line.rstrip}"
            end
          end

          findings << current_finding if current_finding
          findings
        end

        def extract_file_reference(line)
          match = line.match(%r{(?:^|\s)([\w/\-_.]+\.\w+)})
          match ? match[1] : nil
        end

        def extract_line_number(line)
          match = line.match(/(?:line\s+|L)(\d+)/i)
          match ? match[1].to_i : nil
        end
      end
    end
  end
end
