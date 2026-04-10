# frozen_string_literal: true

require "json"

module RubynCode
  module IDE
    # JSON-RPC 2.0 protocol layer for the IDE server.
    # Pure data — no side effects, no I/O beyond JSON serialisation.
    module Protocol
      JSONRPC_VERSION = "2.0"

      # ── Standard JSON-RPC 2.0 error codes ──────────────────────────────
      PARSE_ERROR      = -32_700
      INVALID_REQUEST  = -32_600
      METHOD_NOT_FOUND = -32_601
      INVALID_PARAMS   = -32_602
      INTERNAL_ERROR   = -32_603

      # ── Custom error codes ─────────────────────────────────────────────
      AGENT_BUSY        = -1
      SESSION_NOT_FOUND = -2
      BUDGET_EXCEEDED   = -3

      module_function

      # Parse a JSON string into a request hash.
      # Returns either a valid request hash or an error response hash.
      def parse(line)
        begin
          data = JSON.parse(line)
        rescue JSON::ParserError
          return error(nil, PARSE_ERROR, "Parse error: invalid JSON")
        end

        unless data.is_a?(Hash)
          return error(nil, INVALID_REQUEST, "Invalid request: expected JSON object")
        end

        unless data["jsonrpc"] == JSONRPC_VERSION
          return error(data["id"], INVALID_REQUEST, 'Invalid request: missing or wrong "jsonrpc" version')
        end

        # Response objects (containing "result" or "error") are valid
        # JSON-RPC 2.0 messages that don't carry a "method".
        is_response = data.key?("result") || data.key?("error")

        unless is_response || data["method"].is_a?(String)
          return error(data["id"], INVALID_REQUEST, 'Invalid request: "method" must be a string')
        end

        if data.key?("params") && !data["params"].is_a?(Hash) && !data["params"].is_a?(Array)
          return error(data["id"], INVALID_PARAMS, 'Invalid params: "params" must be an object or array')
        end

        data
      end

      # Build a success response hash.
      def response(id, result)
        {
          "jsonrpc" => JSONRPC_VERSION,
          "id"      => id,
          "result"  => stringify_keys_deep(result)
        }
      end

      # Build an error response hash.
      def error(id, code, message)
        {
          "jsonrpc" => JSONRPC_VERSION,
          "id"      => id,
          "error"   => {
            "code"    => code,
            "message" => message
          }
        }
      end

      # Build a notification hash (no id).
      def notification(method, params)
        {
          "jsonrpc" => JSONRPC_VERSION,
          "method"  => method,
          "params"  => stringify_keys_deep(params)
        }
      end

      # Serialise a hash to a JSON string terminated by a newline.
      def serialize(hash)
        JSON.generate(hash) + "\n"
      end

      # ── Helpers ────────────────────────────────────────────────────────

      # Recursively convert symbol keys to strings so every hash that
      # leaves this module uses string keys for JSON compatibility.
      def stringify_keys_deep(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), memo|
            memo[k.to_s] = stringify_keys_deep(v)
          end
        when Array
          obj.map { |v| stringify_keys_deep(v) }
        else
          obj
        end
      end

      private_class_method :stringify_keys_deep
    end
  end
end
