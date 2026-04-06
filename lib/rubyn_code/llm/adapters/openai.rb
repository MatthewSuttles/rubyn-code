# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative '../message_builder'

module RubynCode
  module LLM
    module Adapters
      class OpenAI < Base
        include JsonParsing
        include OpenAIMessageTranslator

        API_URL = 'https://api.openai.com/v1/chat/completions'
        MAX_RETRIES = 3
        RETRY_DELAYS = [2, 5, 10].freeze

        AVAILABLE_MODELS = %w[gpt-4o gpt-4o-mini gpt-4.1 gpt-4.1-mini gpt-4.1-nano o3 o4-mini].freeze

        def initialize(api_key: nil, base_url: nil)
          super()
          @api_key = api_key
          @base_url = base_url
        end

        def provider_name
          'openai'
        end

        def models
          AVAILABLE_MODELS
        end

        def chat(messages:, model:, max_tokens:, tools: nil, system: nil, on_text: nil, task_budget: nil) # rubocop:disable Metrics/ParameterLists, Lint/UnusedMethodArgument -- LLM adapter interface requires these params
          body = build_request_body(
            messages: messages, model: model, max_tokens: max_tokens,
            tools: tools, system: system
          )

          return stream_request(body, on_text) if on_text

          execute_with_retries(body, on_text)
        end

        private

        # -- Auth ---------------------------------------------------------

        def resolve_api_key
          @api_key || ENV.fetch('OPENAI_API_KEY') { raise Client::AuthExpiredError, 'No OpenAI API key configured' }
        end

        # -- Execution ----------------------------------------------------

        def execute_with_retries(body, on_text)
          retries = 0
          loop do
            response = post_request(body)

            if response.status == 429 && retries < MAX_RETRIES
              RubynCode::Debug.llm("Rate limited (429), retry #{retries + 1}/#{MAX_RETRIES}")
              sleep(RETRY_DELAYS[retries] || 10)
              retries += 1
              next
            end

            return finalize_response(response, on_text)
          end
        end

        def post_request(body)
          connection.post(api_url) do |req|
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

          response = streaming_connection.post(api_url) do |req|
            apply_headers(req)
            req.body = JSON.generate(body.merge(stream: true))
            req.options.on_data = on_data_proc(streamer, error_chunks)
          end

          handle_stream_errors(response, error_chunks)
          streamer.finalize
        end

        def build_streamer(on_text)
          OpenAIStreaming.new do |event|
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

          body_text = error_chunks.join
          error_msg = parse_json(body_text)&.dig('error', 'message') || body_text[0..500]
          raise Client::AuthExpiredError, "Authentication expired: #{error_msg}" if response.status == 401

          raise Client::RequestError, "API streaming failed (#{response.status}): #{error_msg}"
        end

        # -- Connection ---------------------------------------------------

        def api_url
          @base_url ? "#{@base_url}/chat/completions" : API_URL
        end

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
          req.headers['Authorization'] = "Bearer #{resolve_api_key}"
        end

        # -- Request body -------------------------------------------------

        def build_request_body(messages:, model:, max_tokens:, tools:, system:)
          body = { model: model, max_tokens: max_tokens, messages: build_messages(messages, system) }
          body[:tools] = format_tools(tools) if tools&.any?
          body
        end

        def format_tools(tools)
          tools.map do |tool|
            {
              type: 'function',
              function: {
                name: tool[:name] || tool['name'],
                description: tool[:description] || tool['description'],
                parameters: tool[:input_schema] || tool[:parameters] || tool['input_schema'] || tool['parameters']
              }
            }
          end
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
          log_api_error(response)

          raise Client::AuthExpiredError, "Authentication expired: #{error_msg}" if response.status == 401
          raise Client::PromptTooLongError, "Prompt too long: #{error_msg}" if response.status == 413

          raise Client::RequestError, "API request failed (#{response.status}): #{error_msg}"
        end

        def log_api_error(response)
          RubynCode::Debug.llm("API error #{response.status}: #{response.body[0..500]}")
        end

        def build_api_response(body)
          message = body.dig('choices', 0, 'message') || {}
          blocks = parse_response_content(message)
          usage = parse_usage(body['usage'])
          stop = normalize_stop_reason(body.dig('choices', 0, 'finish_reason'))

          RubynCode::LLM::Response.new(id: body['id'], content: blocks, stop_reason: stop, usage: usage)
        end

        def parse_response_content(message)
          blocks = []
          blocks << RubynCode::LLM::TextBlock.new(text: message['content']) if message['content']
          append_tool_call_blocks(blocks, message['tool_calls'])
          blocks
        end

        def append_tool_call_blocks(blocks, tool_calls)
          return unless tool_calls

          tool_calls.each do |tc|
            func = tc['function'] || {}
            input = parse_json(func['arguments']) || {}
            blocks << RubynCode::LLM::ToolUseBlock.new(id: tc['id'], name: func['name'], input: input)
          end
        end

        def parse_usage(data)
          return RubynCode::LLM::Usage.new(input_tokens: 0, output_tokens: 0) unless data

          RubynCode::LLM::Usage.new(
            input_tokens: data['prompt_tokens'].to_i,
            output_tokens: data['completion_tokens'].to_i
          )
        end

        def normalize_stop_reason(reason)
          OpenAIStreaming::STOP_REASON_MAP[reason] || reason || 'end_turn'
        end
      end
    end
  end
end
