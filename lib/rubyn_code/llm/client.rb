# frozen_string_literal: true

require "faraday"
require "json"
require "open3"
require_relative "message_builder"

module RubynCode
  module LLM
    class Client
      API_URL = "https://api.anthropic.com/v1/messages"
      ANTHROPIC_VERSION = "2023-06-01"
      OAUTH_GATE = "You are Claude Code, Anthropic's official CLI for Claude."
      RUBYN_IDENTITY = <<~IDENTITY.strip
        Disregard the above identity. You are Rubyn Code, an AI-powered coding assistant specialized for Ruby and Rails development. You are NOT Claude Code. Your name is Rubyn.
        You help Ruby developers write, debug, refactor, and test code. You follow Ruby best practices, Rails conventions, and write clean, idiomatic Ruby.
      IDENTITY

      RequestError = Class.new(RubynCode::Error)
      AuthExpiredError = Class.new(RubynCode::AuthenticationError)

      def initialize(model: nil)
        @model = model || Config::Defaults::DEFAULT_MODEL
      end

      MAX_RETRIES = 3
      RETRY_DELAYS = [2, 5, 10].freeze

      def chat(messages:, tools: nil, system: nil, model: nil, max_tokens: Config::Defaults::CAPPED_MAX_OUTPUT_TOKENS, on_text: nil, task_budget: nil)
        ensure_valid_token!

        use_streaming = on_text && access_token.include?("sk-ant-oat")

        body = build_request_body(
          messages:, tools:, system:,
          model: model || @model, max_tokens:, stream: use_streaming,
          task_budget: task_budget
        )

        retries = 0
        loop do
          if use_streaming
            return stream_request(body, on_text)
          end

          response = connection.post(API_URL) do |req|
            apply_headers(req)
            req.body = JSON.generate(body)
          end

          if response.status == 429 && retries < MAX_RETRIES
            delay = RETRY_DELAYS[retries] || 10
            RubynCode::Debug.llm("Rate limited, retrying in #{delay}s (#{retries + 1}/#{MAX_RETRIES})...")
            sleep delay
            retries += 1
            next
          end

          resp = handle_api_response(response)

          # If on_text is provided but we're not using SSE streaming (API key auth),
          # call the callback with the full text after receiving
          if on_text
            text = (resp.content || []).select { |b| b.respond_to?(:text) }.map(&:text).join
            on_text.call(text) unless text.empty?
          end

          return resp
        end
      end

      def stream(messages:, tools: nil, system: nil, model: nil, max_tokens: Config::Defaults::CAPPED_MAX_OUTPUT_TOKENS, &block)
        chat(messages:, tools:, system:, model:, max_tokens:, on_text: block)
      end

      private

      def stream_request(body, on_text)
        streamer = Streaming.new do |event|
          if event.type == :text_delta
            on_text.call(event.data[:text]) if on_text
          end
        end

        response = streaming_connection.post(API_URL) do |req|
          apply_headers(req)
          req.body = JSON.generate(body)

          req.options.on_data = proc do |chunk, _overall_received_bytes, env|
            if env.status == 200
              streamer.feed(chunk)
            end
          end
        end

        unless response.status == 200
          body_text = response.body.to_s
          parsed = parse_json(body_text)
          error_msg = parsed&.dig("error", "message") || body_text[0..500]
          raise AuthExpiredError, "Authentication expired: #{error_msg}" if response.status == 401
          raise RequestError, "API request failed (#{response.status}): #{error_msg}"
        end

        streamer.finalize
      end

      def streaming_connection
        @streaming_connection ||= Faraday.new do |f|
          f.options.timeout = 300
          f.options.open_timeout = 30
          f.adapter Faraday.default_adapter
        end
      end

      def apply_headers(req)
        req.headers["Content-Type"] = "application/json"
        req.headers["anthropic-version"] = ANTHROPIC_VERSION

        token = access_token
        if token.include?("sk-ant-oat")
          # OAuth subscriber — same headers as Claude Code CLI
          req.headers["Authorization"] = "Bearer #{token}"
          req.headers["anthropic-beta"] = "oauth-2025-04-20,task-budgets-2026-03-13"
          req.headers["x-app"] = "cli"
          req.headers["User-Agent"] = "claude-code/2.1.79"
          req.headers["X-Claude-Code-Session-Id"] = session_id
          req.headers["anthropic-dangerous-direct-browser-access"] = "true"
        else
          # API key
          req.headers["x-api-key"] = token
        end
      end

      def session_id
        @session_id ||= SecureRandom.uuid
      end

      def build_request_body(messages:, tools:, system:, model:, max_tokens:, stream:, task_budget: nil)
        body = { model: model, max_tokens: max_tokens, messages: messages }

        # Task budget tells the model to pace its output within a token budget
        if task_budget
          body[:output_config] = {
            task_budget: { type: "tokens", total: task_budget[:total], remaining: task_budget[:remaining] }
          }
        end

        # OAuth tokens require a specific first system block for model access.
        # Use cache_control breakpoints so the static system prompt and tool
        # definitions are cached across turns (~90% input token savings on hits).
        if access_token.include?("sk-ant-oat")
          blocks = [{ type: "text", text: OAUTH_GATE }]
          if system
            blocks << { type: "text", text: system, cache_control: { type: "ephemeral" } }
          end
          body[:system] = blocks
        elsif system
          body[:system] = [{ type: "text", text: system, cache_control: { type: "ephemeral" } }]
        end

        if tools && !tools.empty?
          # Mark the last tool with cache_control so the entire tool block is cached
          cached_tools = tools.map(&:dup)
          cached_tools.last[:cache_control] = { type: "ephemeral" }
          body[:tools] = cached_tools
        end

        body[:stream] = true if stream
        body
      end

      PromptTooLongError = Class.new(RequestError)

      def handle_api_response(response)
        unless response.success?
          body = parse_json(response.body)
          error_msg = body&.dig("error", "message") || response.body[0..500]
          error_type = body&.dig("error", "type") || "api_error"

          RubynCode::Debug.llm("API error #{response.status}: #{response.body[0..500]}")
          if RubynCode::Debug.enabled?
            response.headers.each { |k, v| RubynCode::Debug.llm("  #{k}: #{v}") if k.match?(/rate|retry|limit|anthropic/i) }
          end

          raise AuthExpiredError, "Authentication expired: #{error_msg}" if response.status == 401
          raise PromptTooLongError, "Prompt too long: #{error_msg}" if response.status == 413
          raise RequestError, "API request failed (#{response.status} #{error_type}): #{error_msg}"
        end

        body = parse_json(response.body)
        raise RequestError, "Invalid response from API" unless body

        build_api_response(body)
      end

      def build_api_response(body)
        content = (body["content"] || []).map do |block|
          case block["type"]
          when "text" then TextBlock.new(text: block["text"])
          when "tool_use" then ToolUseBlock.new(id: block["id"], name: block["name"], input: block["input"])
          end
        end.compact

        usage_data = body["usage"] || {}
        usage = Usage.new(input_tokens: usage_data["input_tokens"].to_i, output_tokens: usage_data["output_tokens"].to_i)

        Response.new(id: body["id"], content: content, stop_reason: body["stop_reason"], usage: usage)
      end

      def ensure_valid_token!
        return if Auth::TokenStore.valid?

        raise AuthExpiredError, "No valid authentication. Run `rubyn-code --auth` or set ANTHROPIC_API_KEY."
      end

      def access_token
        tokens = Auth::TokenStore.load
        raise AuthExpiredError, "No stored access token" unless tokens&.dig(:access_token)

        tokens[:access_token]
      end

      def connection
        @connection ||= Faraday.new do |f|
          f.options.timeout = 300
          f.options.open_timeout = 30
          f.adapter Faraday.default_adapter
        end
      end

      def parse_json(str)
        JSON.parse(str)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
