# frozen_string_literal: true

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
          base_branch = params["baseBranch"] || "main"
          focus       = params["focus"] || "all"
          session_id  = params["sessionId"] || SecureRandom.uuid

          Thread.new do
            run_review(session_id, base_branch, focus)
          end

          { "accepted" => true, "sessionId" => session_id }
        end

        private

        def run_review(session_id, base_branch, focus)
          @server.notify("agent/status", {
            "sessionId" => session_id,
            "status"    => "reviewing"
          })

          workspace = @server.workspace_path || Dir.pwd
          review_tool = Tools::ReviewPr.new(project_root: workspace)
          result = review_tool.execute(base_branch: base_branch, focus: focus)

          # Parse the review output into individual findings and emit them
          findings = extract_findings(result)
          findings.each_with_index do |finding, idx|
            @server.notify("review/finding", {
              "sessionId" => session_id,
              "index"     => idx,
              "severity"  => finding[:severity],
              "message"   => finding[:message],
              "file"      => finding[:file],
              "line"      => finding[:line]
            })
          end

          @server.notify("agent/status", {
            "sessionId" => session_id,
            "status"    => "done",
            "summary"   => "Review complete: #{findings.size} finding(s)"
          })
        rescue StandardError => e
          $stderr.puts "[ReviewHandler] error: #{e.message}"
          @server.notify("agent/status", {
            "sessionId" => session_id,
            "status"    => "error",
            "error"     => e.message
          })
        end

        # Extract structured findings from the raw review text.
        # Looks for severity markers like [critical], [warning], etc.
        SEVERITY_PATTERN = /\[(critical|warning|suggestion|nitpick)\]/i

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
                message:  line.strip,
                file:     extract_file_reference(line),
                line:     extract_line_number(line)
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
          match = line.match(/(?:^|\s)([\w\/\-_.]+\.\w+)/)
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
