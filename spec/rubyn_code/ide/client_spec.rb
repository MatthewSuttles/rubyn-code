# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"
require "stringio"
require "json"
require_relative "support/server_helper"

RSpec.describe RubynCode::IDE::Client do
  include IDEServerHelper

  let(:stdin_io)  { StringIO.new }
  let(:stdout_io) { StringIO.new }
  let(:server)    { build_test_server(stdin_io, stdout_io) }
  let(:client)    { server.ide_client }

  describe "#request" do
    it "sends a JSON-RPC request and resolves when response arrives" do
      result = nil
      requester = Thread.new do
        result = client.request("ide/readSelection", {}, timeout: 5)
      end

      # Give the request time to be sent
      sleep 0.1

      # Read the request that was written to stdout
      stdout_io.rewind
      messages = read_all_messages(stdout_io)
      req = messages.find { |m| m["method"] == "ide/readSelection" }
      expect(req).not_to be_nil
      expect(req["id"]).to be >= 1000

      # Simulate the extension responding
      client.resolve(req["id"], result: { "text" => "hello", "file" => "test.rb" })

      requester.join(2)
      expect(result).to eq({ "text" => "hello", "file" => "test.rb" })
    end

    it "raises on timeout" do
      expect {
        client.request("ide/readSelection", {}, timeout: 0.1)
      }.to raise_error(RubynCode::IDE::Client::TimeoutError)
    end

    it "raises on RPC error response" do
      requester = Thread.new do
        client.request("ide/readSelection", {}, timeout: 5)
      end

      sleep 0.1

      stdout_io.rewind
      messages = read_all_messages(stdout_io)
      req = messages.find { |m| m["method"] == "ide/readSelection" }

      client.resolve(req["id"], error: { "code" => -32603, "message" => "Internal error" })

      expect { requester.value }.to raise_error(StandardError, /RPC error/)
    end
  end

  describe "#pending?" do
    it "tracks pending requests" do
      requester = Thread.new do
        client.request("ide/getOpenTabs", {}, timeout: 5)
      end

      sleep 0.1

      stdout_io.rewind
      messages = read_all_messages(stdout_io)
      req = messages.find { |m| m["method"] == "ide/getOpenTabs" }

      expect(client.pending?(req["id"])).to be true

      client.resolve(req["id"], result: { "tabs" => [] })
      requester.join(2)

      expect(client.pending?(req["id"])).to be false
    end
  end

  describe "server dispatch routing" do
    it "routes response messages to the client" do
      result = nil
      requester = Thread.new do
        result = client.request("ide/readActiveFile", {}, timeout: 5)
      end

      sleep 0.1

      stdout_io.rewind
      messages = read_all_messages(stdout_io)
      req = messages.find { |m| m["method"] == "ide/readActiveFile" }

      # Simulate dispatching a response through the server
      response_line = JSON.generate({
        "jsonrpc" => "2.0",
        "id" => req["id"],
        "result" => { "path" => "/test.rb", "content" => "puts 'hi'", "language" => "ruby" }
      })
      server.public_handle_line(response_line)

      requester.join(2)
      expect(result["path"]).to eq("/test.rb")
      expect(result["content"]).to eq("puts 'hi'")
    end
  end
end
