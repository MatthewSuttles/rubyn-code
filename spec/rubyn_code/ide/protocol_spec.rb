# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/protocol"

RSpec.describe RubynCode::IDE::Protocol do
  let(:protocol) { described_class }

  describe ".parse" do
    context "with a valid request" do
      it "returns a hash with jsonrpc, id, and method" do
        result = protocol.parse('{"jsonrpc":"2.0","id":1,"method":"test"}')
        expect(result).to be_a(Hash)
        expect(result["jsonrpc"]).to eq("2.0")
        expect(result["id"]).to eq(1)
        expect(result["method"]).to eq("test")
      end
    end

    context "with a request that includes params" do
      it "includes params in the parsed result" do
        json = '{"jsonrpc":"2.0","id":2,"method":"doStuff","params":{"foo":"bar"}}'
        result = protocol.parse(json)
        expect(result["params"]).to eq({ "foo" => "bar" })
      end

      it "accepts array params" do
        json = '{"jsonrpc":"2.0","id":3,"method":"doStuff","params":["a","b"]}'
        result = protocol.parse(json)
        expect(result["params"]).to eq(%w[a b])
      end
    end

    context "with a notification (no id)" do
      it "parses a valid notification" do
        json = '{"jsonrpc":"2.0","method":"update","params":{"key":"val"}}'
        result = protocol.parse(json)
        expect(result["method"]).to eq("update")
        expect(result).not_to have_key("id")
      end
    end

    context "with invalid JSON" do
      it "returns a parse error (-32700)" do
        result = protocol.parse("not valid json {{{")
        expect(result["error"]["code"]).to eq(-32_700)
        expect(result["error"]["message"]).to include("Parse error")
      end
    end

    context "with missing jsonrpc field" do
      it "returns an invalid request error (-32600)" do
        result = protocol.parse('{"id":1,"method":"test"}')
        expect(result["error"]["code"]).to eq(-32_600)
      end
    end

    context "with wrong jsonrpc version" do
      it "returns an invalid request error" do
        result = protocol.parse('{"jsonrpc":"1.0","id":1,"method":"test"}')
        expect(result["error"]["code"]).to eq(-32_600)
        expect(result["error"]["message"]).to include("jsonrpc")
      end
    end

    context "with missing method" do
      it "returns an invalid request error" do
        result = protocol.parse('{"jsonrpc":"2.0","id":1}')
        expect(result["error"]["code"]).to eq(-32_600)
        expect(result["error"]["message"]).to include("method")
      end
    end

    context "with non-string method" do
      it "returns an invalid request error" do
        result = protocol.parse('{"jsonrpc":"2.0","id":1,"method":42}')
        expect(result["error"]["code"]).to eq(-32_600)
        expect(result["error"]["message"]).to include("method")
      end

      it "returns invalid request for null method" do
        result = protocol.parse('{"jsonrpc":"2.0","id":1,"method":null}')
        expect(result["error"]["code"]).to eq(-32_600)
      end
    end

    context "with invalid params type" do
      it "returns an invalid params error (-32602) for string params" do
        result = protocol.parse('{"jsonrpc":"2.0","id":1,"method":"test","params":"bad"}')
        expect(result["error"]["code"]).to eq(-32_602)
        expect(result["error"]["message"]).to include("params")
      end

      it "returns an invalid params error for numeric params" do
        result = protocol.parse('{"jsonrpc":"2.0","id":1,"method":"test","params":42}')
        expect(result["error"]["code"]).to eq(-32_602)
      end
    end

    context "with a response object (has result, no method)" do
      it "parses successfully without requiring method" do
        json = '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}'
        result = protocol.parse(json)
        expect(result["result"]).to eq({ "ok" => true })
        expect(result).not_to have_key("error")
      end
    end

    context "with an error response object" do
      it "parses successfully without requiring method" do
        json = '{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"fail"}}'
        result = protocol.parse(json)
        expect(result["error"]["code"]).to eq(-1)
      end
    end
  end

  describe ".response" do
    it "builds a correct response with string keys" do
      resp = protocol.response(42, { ok: true, data: "hello" })
      expect(resp["jsonrpc"]).to eq("2.0")
      expect(resp["id"]).to eq(42)
      expect(resp["result"]).to eq({ "ok" => true, "data" => "hello" })
    end

    it "stringifies nested symbol keys" do
      resp = protocol.response(1, { outer: { inner: "value" } })
      expect(resp["result"]["outer"]["inner"]).to eq("value")
    end
  end

  describe ".error" do
    it "builds a correct error response" do
      err = protocol.error(99, -32_600, "bad request")
      expect(err["jsonrpc"]).to eq("2.0")
      expect(err["id"]).to eq(99)
      expect(err["error"]["code"]).to eq(-32_600)
      expect(err["error"]["message"]).to eq("bad request")
    end

    it "accepts nil id for notifications" do
      err = protocol.error(nil, -32_700, "parse error")
      expect(err["id"]).to be_nil
    end
  end

  describe ".notification" do
    it "builds a notification without an id field" do
      notif = protocol.notification("stream/text", { text: "hello" })
      expect(notif["jsonrpc"]).to eq("2.0")
      expect(notif["method"]).to eq("stream/text")
      expect(notif["params"]).to eq({ "text" => "hello" })
      expect(notif).not_to have_key("id")
    end
  end

  describe ".serialize" do
    it "outputs a JSON string terminated with a newline" do
      hash = { "jsonrpc" => "2.0", "id" => 1, "result" => {} }
      serialized = protocol.serialize(hash)
      expect(serialized).to end_with("\n")
      expect(JSON.parse(serialized.chomp)).to eq(hash)
    end

    it "produces valid JSON" do
      hash = { "a" => [1, 2, 3], "b" => { "c" => true } }
      parsed = JSON.parse(protocol.serialize(hash).chomp)
      expect(parsed).to eq(hash)
    end
  end

  describe "round-trip" do
    it "parse(serialize(response(1, {ok: true}))) yields the original response" do
      original = protocol.response(1, { ok: true })
      serialized = protocol.serialize(original)
      parsed = protocol.parse(serialized)

      # The parsed result is a response object with "result" key, so it should
      # pass validation (no method required for response objects).
      expect(parsed["jsonrpc"]).to eq("2.0")
      expect(parsed["id"]).to eq(1)
      expect(parsed["result"]["ok"]).to eq(true)
    end
  end

  describe ".stringify_keys_deep" do
    # Access via Protocol.send since it's a private class method
    it "converts nested symbol keys to strings" do
      input = { foo: { bar: [{ baz: 1 }] } }
      result = protocol.send(:stringify_keys_deep, input)
      expect(result).to eq({ "foo" => { "bar" => [{ "baz" => 1 }] } })
    end

    it "leaves strings, numbers, and booleans unchanged" do
      expect(protocol.send(:stringify_keys_deep, "hello")).to eq("hello")
      expect(protocol.send(:stringify_keys_deep, 42)).to eq(42)
      expect(protocol.send(:stringify_keys_deep, true)).to eq(true)
      expect(protocol.send(:stringify_keys_deep, nil)).to be_nil
    end

    it "handles arrays of hashes" do
      input = [{ a: 1 }, { b: 2 }]
      result = protocol.send(:stringify_keys_deep, input)
      expect(result).to eq([{ "a" => 1 }, { "b" => 2 }])
    end

    it "handles deeply nested structures" do
      input = { l1: { l2: { l3: { l4: "deep" } } } }
      result = protocol.send(:stringify_keys_deep, input)
      expect(result).to eq({ "l1" => { "l2" => { "l3" => { "l4" => "deep" } } } })
    end
  end

  describe "error code constants" do
    it "defines PARSE_ERROR as -32700" do
      expect(protocol::PARSE_ERROR).to eq(-32_700)
    end

    it "defines INVALID_REQUEST as -32600" do
      expect(protocol::INVALID_REQUEST).to eq(-32_600)
    end

    it "defines METHOD_NOT_FOUND as -32601" do
      expect(protocol::METHOD_NOT_FOUND).to eq(-32_601)
    end

    it "defines INVALID_PARAMS as -32602" do
      expect(protocol::INVALID_PARAMS).to eq(-32_602)
    end

    it "defines INTERNAL_ERROR as -32603" do
      expect(protocol::INTERNAL_ERROR).to eq(-32_603)
    end

    it "defines AGENT_BUSY as -1" do
      expect(protocol::AGENT_BUSY).to eq(-1)
    end

    it "defines SESSION_NOT_FOUND as -2" do
      expect(protocol::SESSION_NOT_FOUND).to eq(-2)
    end

    it "defines BUDGET_EXCEEDED as -3" do
      expect(protocol::BUDGET_EXCEEDED).to eq(-3)
    end
  end
end
