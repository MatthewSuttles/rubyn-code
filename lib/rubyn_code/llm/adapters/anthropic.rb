# frozen_string_literal: true

require 'faraday'
require 'json'
require 'securerandom'
require_relative '../message_builder'

module RubynCode
  module LLM
    module Adapters
      class Anthropic < Base
        include JsonParsing
        include PromptCaching

        API_URL = 'https://api.anthropic.com/v1/messages'
        ANTHROPIC_VERSION = '2023-06-01'
        MAX_RETRIES = 3
        RETRY_DELAYS = [2, 5, 10].freeze

        AVAILABLE_MODELS = %w[
          claude-sonnet-4-20250514
          claude-opus-4-6
          claude-haiku-4-20250506
        ].freeze

        def provider_name
          'anthropic'
        end

        def models
          AVAILABLE_MODELS
        end

        def chat(messages:, model:, max_tokens:, tools: nil, system: nil, on_text: nil, task_budget: nil) # rubocop:disable Metrics/ParameterLists -- mirrors LLM adapter interface
          ensure_valid_token!
          use_streaming = on_text && oauth_token?

          body = build_request_body(
            messages: messages, tools: tools, system: system,
            model: model, max_tokens: max_tokens,
            stream: use_streaming, task_budget: task_budget
          )

          return stream_request(body, on_text) if use_streaming

          execute_with_retries(body, on_text)
        end

        private

        # -- Auth ---------------------------------------------------------

        def oauth_token?
          access_token.include?('sk-ant-oat')
        end

        def ensure_valid_token!
          return if Auth::TokenStore.valid?

          raise Client::AuthExpiredError,
                'No valid authentication. Run `rubyn-code --auth` or set ANTHROPIC_API_KEY.'
        end

        def access_token
          tokens = Auth::TokenStore.load
          raise Client::AuthExpiredError, 'No stored access token' unless tokens&.dig(:access_token)

          tokens[:access_token]
        end

        # -- Request execution --------------------------------------------

        def execute_with_retries(body, on_text)
          retries = 0
          loop do
            response = post_request(body)

            if response.status == 429 && retries < MAX_RETRIES
              delay = RETRY_DELAYS[retries] || 10
              RubynCode::Debug.llm("Rate limited, retrying in #{delay}s (#{retries + 1}/#{MAX_RETRIES})...")
              sleep delay
              retries += 1
              next
            end

            return finalize_response(response, on_text)
          end
        end

        def post_request(body)
          connection.post(API_URL) do |req|
            apply_headers(req)
            req.body = JSON.generate(body)
          end
        end

        def finalize_response(response, on_text)
          resp = handle_api_response(response)
          emit_full_text(resp, on_text)
          resp
        end

        def emit_full_text(resp, on_text)
          return unless on_text

          text = resp.content.select { |b| b.respond_to?(:text) }.map(&:text).join
          on_text.call(text) unless text.empty?
        end

        # -- Streaming ----------------------------------------------------

        def stream_request(body, on_text)
          streamer = build_streamer(on_text)
          error_chunks = []

          response = streaming_connection.post(API_URL) do |req|
            apply_headers(req)
            req.body = JSON.generate(body)
            req.options.on_data = on_data_proc(streamer, error_chunks)
          end

          handle_stream_errors(response, error_chunks)
          streamer.finalize
        end

        def build_streamer(on_text)
          AnthropicStreaming.new do |event|
            on_text&.call(event.data[:text]) if event.type == :text_delta
          end
        end

        def on_data_proc(streamer, error_chunks)
          proc do |chunk, _bytes, env|
            env.status == 200 ? streamer.feed(chunk) : error_chunks << chunk
          end
        end

        def handle_stream_errors(response, error_chunks)
          return if response.status == 200

          error_msg = extract_error_message(error_chunks.join)

          raise Client::AuthExpiredError, "Authentication expired: #{error_msg}" if response.status == 401
          raise Client::PromptTooLongError, "Prompt too long: #{error_msg}" if response.status == 413

          raise Client::RequestError,
                "API streaming request failed (#{response.status}): #{error_msg}"
        end

        def extract_error_message(body_text)
          parsed = parse_json(body_text)
          parsed&.dig('error', 'message') || body_text[0..500]
        end

        # -- HTTP ---------------------------------------------------------

        def connection
          @connection ||= build_faraday_connection
        end

        def streaming_connection
          @streaming_connection ||= build_faraday_connection
        end

        def build_faraday_connection
          Faraday.new do |f|
            f.options.timeout = 300
            f.options.open_timeout = 30
            f.adapter Faraday.default_adapter
          end
        end

        # -- Headers ------------------------------------------------------

        def apply_headers(req)
          req.headers['Content-Type'] = 'application/json'
          req.headers['anthropic-version'] = ANTHROPIC_VERSION
          oauth_token? ? apply_oauth_headers(req) : apply_api_key_headers(req)
        end

        def apply_oauth_headers(req)
          req.headers['Authorization'] = "Bearer #{access_token}"
          req.headers['anthropic-beta'] = 'oauth-2025-04-20'
          req.headers['x-app'] = 'cli'
          req.headers['User-Agent'] = 'claude-code/2.1.79'
          req.headers['X-Claude-Code-Session-Id'] = session_id
          req.headers['anthropic-dangerous-direct-browser-access'] = 'true'
        end

        def apply_api_key_headers(req)
          req.headers['x-api-key'] = access_token
        end

        def session_id
          @session_id ||= SecureRandom.uuid
        end

        # -- Request body -------------------------------------------------

        def build_request_body(messages:, tools:, system:, model:, max_tokens:, stream:, **_opts) # rubocop:disable Metrics/ParameterLists -- API request builder mirrors Claude API params
          body = { model: model, max_tokens: max_tokens }
          apply_system_blocks(body, system)
          apply_tool_cache(body, tools)
          body[:messages] = add_message_cache_breakpoint(messages)
          body[:stream] = true if stream
          body
        end

        # -- Response parsing ---------------------------------------------

        def handle_api_response(response)
          raise_on_error(response) unless response.success?

          body = parse_json(response.body)
          raise Client::RequestError, 'Invalid response from API' unless body

          build_api_response(body)
        end

        def raise_on_error(response)
          body = parse_json(response.body)
          error_msg = body&.dig('error', 'message') || response.body[0..500]
          error_type = body&.dig('error', 'type') || 'api_error'

          log_api_error(response)
          raise Client::AuthExpiredError, "Authentication expired: #{error_msg}" if response.status == 401
          raise Client::PromptTooLongError, "Prompt too long: #{error_msg}" if response.status == 413

          raise Client::RequestError, "API request failed (#{response.status} #{error_type}): #{error_msg}"
        end

        def log_api_error(response)
          RubynCode::Debug.llm("API error #{response.status}: #{response.body[0..500]}")
          return unless RubynCode::Debug.enabled?

          response.headers.each do |k, v|
            RubynCode::Debug.llm("  #{k}: #{v}") if k.match?(/rate|retry|limit|anthropic/i)
          end
        end

        def build_api_response(body)
          content = parse_content_blocks(body['content'])
          usage = parse_usage(body['usage'])
          Response.new(id: body['id'], content: content, stop_reason: body['stop_reason'], usage: usage)
        end

        def parse_content_blocks(blocks)
          (blocks || []).filter_map do |block|
            case block['type']
            when 'text' then TextBlock.new(text: block['text'])
            when 'tool_use'
              ToolUseBlock.new(id: block['id'], name: block['name'], input: block['input'])
            end
          end
        end

        def parse_usage(data)
          return Usage.new(input_tokens: 0, output_tokens: 0) unless data

          Usage.new(
            input_tokens: data['input_tokens'].to_i,
            output_tokens: data['output_tokens'].to_i,
            cache_creation_input_tokens: data['cache_creation_input_tokens'].to_i,
            cache_read_input_tokens: data['cache_read_input_tokens'].to_i
          )
        end
      end
    end
  end
end
