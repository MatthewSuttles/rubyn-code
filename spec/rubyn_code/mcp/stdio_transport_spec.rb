# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::MCP::StdioTransport do
  let(:stdin) { instance_double(IO, write: nil, flush: nil, close: nil, closed?: false) }
  let(:stdout) { instance_double(IO, close: nil, closed?: false) }
  let(:stderr) { instance_double(IO, close: nil, closed?: false) }
  let(:wait_thread) { double("Process::Waiter", alive?: true, join: nil, pid: 12345) }

  subject(:transport) do
    described_class.new(command: "mcp-server", args: ["--stdio"], timeout: 2)
  end

  before do
    allow(Open3).to receive(:popen3).and_return([stdin, stdout, stderr, wait_thread])
  end

  describe "#send_request" do
    before { transport.start! }

    it "writes JSON-RPC to stdin and reads response" do
      response_json = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "result" => { "tools" => [] } })
      allow(stdout).to receive(:gets).and_return("#{response_json}\n")

      result = transport.send_request("tools/list")
      expect(result).to eq({ "tools" => [] })
    end

    it "raises TransportError on server error response" do
      error_json = JSON.generate({
        "jsonrpc" => "2.0", "id" => 1,
        "error" => { "code" => -32600, "message" => "Invalid" }
      })
      allow(stdout).to receive(:gets).and_return("#{error_json}\n")

      expect { transport.send_request("bad/method") }
        .to raise_error(RubynCode::MCP::StdioTransport::TransportError, /Invalid/)
    end
  end

  describe '#stop!' do
    it 'closes streams and joins the wait thread' do
      transport.start!
      allow(wait_thread).to receive(:alive?).and_return(true, true, false)
      allow(stdin).to receive(:write)
      allow(stdin).to receive(:flush)

      transport.stop!

      expect(stdin).to have_received(:close).at_least(:once)
      expect(stdout).to have_received(:close).at_least(:once)
      expect(stderr).to have_received(:close).at_least(:once)
      expect(wait_thread).to have_received(:join)
    end

    it 'is safe to call when already stopped' do
      transport.start!
      allow(wait_thread).to receive(:alive?).and_return(false)
      allow(stdin).to receive(:closed?).and_return(true)
      allow(stdout).to receive(:closed?).and_return(true)
      allow(stderr).to receive(:closed?).and_return(true)

      expect { transport.stop! }.not_to raise_error
    end
  end
end
