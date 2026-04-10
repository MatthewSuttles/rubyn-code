# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "stringio"
require "json"
require_relative "support/server_helper"

RSpec.describe RubynCode::IDE::Server do
  include IDEServerHelper

  let(:stdin_io)  { StringIO.new }
  let(:stdout_io) { StringIO.new }
  let(:server)    { build_test_server(stdin_io, stdout_io) }

  # Helper to dispatch a single line through the server
  def dispatch(line)
    server.public_handle_line(line)
  end

  def json_request(method, params = {}, id: 1)
    JSON.generate({ "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params })
  end

  def collect_responses
    stdout_io.rewind
    read_all_messages(stdout_io)
  end

  describe "initialization" do
    it "creates a server instance" do
      expect(server).to be_a(RubynCode::IDE::Server)
    end

    it "registers all handlers" do
      RubynCode::IDE::Handlers::REGISTRY.each_key do |method_name|
        expect(server.handler_instances[method_name]).not_to be_nil,
          "expected handler for '#{method_name}' to be registered"
      end
    end

    it "starts with nil workspace_path" do
      expect(server.workspace_path).to be_nil
    end

    it "starts with empty client_capabilities" do
      expect(server.client_capabilities).to eq({})
    end
  end

  describe "message dispatch" do
    it "writes a JSON-RPC response to stdout for a request with id" do
      # Stub the initialize handler to avoid side effects
      allow(Dir).to receive(:exist?).and_return(false)
      allow(RubynCode::Tools::Registry).to receive(:load_all!)
      allow(RubynCode::Tools::Registry).to receive(:tool_names).and_return([])
      allow_any_instance_of(RubynCode::IDE::Handlers::InitializeHandler)
        .to receive(:call).and_return({ "serverVersion" => "test" })

      dispatch(json_request("initialize", {}, id: 1))

      responses = collect_responses
      expect(responses.size).to eq(1)
      expect(responses.first["jsonrpc"]).to eq("2.0")
      expect(responses.first["id"]).to eq(1)
      expect(responses.first["result"]["serverVersion"]).to eq("test")
    end
  end

  describe "initialize method" do
    before do
      allow(Dir).to receive(:exist?).and_return(false)
      allow(Dir).to receive(:chdir)
      allow(RubynCode::Tools::Registry).to receive(:load_all!)
      allow(RubynCode::Tools::Registry).to receive(:tool_names).and_return(%w[read_file write_file])
      # Stub Skills::Catalog
      catalog_double = instance_double("RubynCode::Skills::Catalog", available: [])
      allow(RubynCode::Skills::Catalog).to receive(:new).and_return(catalog_double)
    end

    it "returns server capabilities" do
      dispatch(json_request("initialize", { "extensionVersion" => "1.0.0" }, id: 1))

      responses = collect_responses
      result = responses.first["result"]
      expect(result["capabilities"]).to be_a(Hash)
      expect(result["capabilities"]["streaming"]).to eq(true)
      expect(result["capabilities"]["review"]).to eq(true)
      expect(result["capabilities"]["toolApproval"]).to eq(true)
      expect(result["capabilities"]["editApproval"]).to eq(true)
    end
  end

  describe "shutdown" do
    it "responds with shutdown confirmation" do
      dispatch(json_request("shutdown", {}, id: 10))

      responses = collect_responses
      expect(responses.first["result"]["shutdown"]).to eq(true)
    end

    it "signals the server to stop" do
      expect(server).to receive(:stop!).and_call_original
      dispatch(json_request("shutdown", {}, id: 10))
    end
  end

  describe "unknown method" do
    it "returns method not found error (-32601)" do
      dispatch(json_request("nonExistentMethod", {}, id: 5))

      responses = collect_responses
      expect(responses.first["error"]["code"]).to eq(-32_601)
      expect(responses.first["error"]["message"]).to include("Method not found")
    end
  end

  describe "invalid JSON on stdin" do
    it "returns a parse error response" do
      dispatch("this is not json at all")

      responses = collect_responses
      expect(responses.first["error"]["code"]).to eq(-32_700)
    end
  end

  describe "#notify" do
    it "writes a notification to stdout" do
      server.notify("stream/text", { "text" => "hello" })

      responses = collect_responses
      notif = responses.first
      expect(notif["jsonrpc"]).to eq("2.0")
      expect(notif["method"]).to eq("stream/text")
      expect(notif["params"]["text"]).to eq("hello")
      expect(notif).not_to have_key("id")
    end
  end

  describe "mutex protection" do
    it "does not interleave concurrent notify calls" do
      threads = 10.times.map do |i|
        Thread.new do
          server.notify("test/event", { "index" => i })
        end
      end
      threads.each(&:join)

      responses = collect_responses
      expect(responses.size).to eq(10)
      # Each response should be valid JSON (not interleaved)
      responses.each do |resp|
        expect(resp["jsonrpc"]).to eq("2.0")
        expect(resp["method"]).to eq("test/event")
      end
    end
  end

  describe "handler registration" do
    it "registers handlers via on()" do
      called = false
      server.on("custom/method") { |_params, _id| called = true; { "ok" => true } }

      dispatch(json_request("custom/method", {}, id: 20))
      expect(called).to be true
    end

    it "overrides existing handler when re-registered" do
      server.on("custom/method") { |_params, _id| { "version" => 1 } }
      server.on("custom/method") { |_params, _id| { "version" => 2 } }

      dispatch(json_request("custom/method", {}, id: 21))
      responses = collect_responses
      expect(responses.first["result"]["version"]).to eq(2)
    end
  end

  describe "multiple messages" do
    it "handles several requests and produces responses for each" do
      # Register a simple echo handler
      server.on("echo") { |params, _id| { "echo" => params["msg"] } }

      dispatch(json_request("echo", { "msg" => "first" }, id: 1))
      dispatch(json_request("echo", { "msg" => "second" }, id: 2))
      dispatch(json_request("echo", { "msg" => "third" }, id: 3))

      responses = collect_responses
      expect(responses.size).to eq(3)
      expect(responses.map { |r| r["result"]["echo"] }).to eq(%w[first second third])
    end
  end

  describe "read_loop with StringIO" do
    it "skips empty lines gracefully" do
      server.on("ping") { |_params, _id| { "pong" => true } }

      input = StringIO.new([
        "",
        json_request("ping", {}, id: 1),
        "   ",
        json_request("ping", {}, id: 2),
        ""
      ].join("\n"))

      test_server = build_test_server(input, stdout_io)
      test_server.on("ping") { |_params, _id| { "pong" => true } }

      # Override @running so the loop will start
      test_server.instance_variable_set(:@running, true)
      test_server.send(:read_loop)

      responses = collect_responses
      expect(responses.size).to eq(2)
      expect(responses.all? { |r| r["result"]["pong"] == true }).to be true
    end
  end

  describe "handler_instance" do
    it "returns the handler instance for a known short name" do
      handler = server.handler_instance(:prompt)
      expect(handler).to be_a(RubynCode::IDE::Handlers::PromptHandler)
    end

    it "returns nil for an unknown short name" do
      handler = server.handler_instance(:nonexistent)
      expect(handler).to be_nil
    end
  end

  describe "#stop!" do
    it "sets the running flag to false" do
      server.instance_variable_set(:@running, true)
      server.stop!
      expect(server.instance_variable_get(:@running)).to be false
    end
  end

  describe "error handling during dispatch" do
    it "returns an internal error when a handler raises" do
      server.on("boom") { |_params, _id| raise StandardError, "kaboom" }

      dispatch(json_request("boom", {}, id: 99))

      responses = collect_responses
      expect(responses.first["error"]["code"]).to eq(-32_603)
      expect(responses.first["error"]["message"]).to include("kaboom")
    end
  end

  describe "notification dispatch (no id)" do
    it "does not send a response for notifications to unknown methods" do
      notification_json = JSON.generate({
        "jsonrpc" => "2.0",
        "method"  => "unknownNotification",
        "params"  => {}
      })

      dispatch(notification_json)

      responses = collect_responses
      # Notifications to unknown methods should be silently ignored (no error response)
      expect(responses).to be_empty
    end
  end
end
