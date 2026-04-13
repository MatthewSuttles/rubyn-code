# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::InitializeHandler do
  let(:server) { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  before do
    allow(RubynCode::Tools::Registry).to receive(:load_all!)
    allow(RubynCode::Tools::Registry).to receive(:tool_names).and_return(%w[read_file write_file])
    catalog_double = instance_double("RubynCode::Skills::Catalog", available: [double, double])
    allow(RubynCode::Skills::Catalog).to receive(:new).and_return(catalog_double)
    allow(Dir).to receive(:chdir)
    allow(Dir).to receive(:exist?).and_return(true)
    allow(Dir).to receive(:pwd).and_return("/test/workspace")
  end

  describe "basic initialization" do
    it "returns capabilities hash" do
      result = handler.call({})
      expect(result["capabilities"]).to be_a(Hash)
      expect(result["capabilities"]["streaming"]).to eq(true)
      expect(result["capabilities"]["review"]).to eq(true)
      expect(result["capabilities"]["memory"]).to eq(true)
      expect(result["capabilities"]["teams"]).to eq(true)
      expect(result["capabilities"]["toolApproval"]).to eq(true)
      expect(result["capabilities"]["editApproval"]).to eq(true)
    end

    it "returns server version" do
      result = handler.call({})
      expect(result["serverVersion"]).to eq(RubynCode::VERSION)
    end

    it "returns protocol version" do
      result = handler.call({})
      expect(result["protocolVersion"]).to eq("1.0")
    end

    it "returns tool count" do
      result = handler.call({})
      expect(result["capabilities"]["tools"]).to eq(2)
    end

    it "returns skill count" do
      result = handler.call({})
      expect(result["capabilities"]["skills"]).to eq(2)
    end
  end

  describe "workspace path" do
    it "calls Dir.chdir with the provided workspacePath" do
      expect(Dir).to receive(:chdir).with("/my/project")
      handler.call({ "workspacePath" => "/my/project" })
    end

    it "sets workspace_path on the server" do
      handler.call({ "workspacePath" => "/my/project" })
      expect(server.workspace_path).to eq("/my/project")
    end

    it "returns the workspace path in the result" do
      result = handler.call({ "workspacePath" => "/my/project" })
      expect(result["workspacePath"]).to eq("/test/workspace")
    end
  end

  describe "missing workspacePath" do
    it "does not call Dir.chdir when workspacePath is nil" do
      expect(Dir).not_to receive(:chdir)
      handler.call({})
    end

    it "does not set workspace_path when nil" do
      handler.call({})
      expect(server.workspace_path).to be_nil
    end

    it "does not chdir when directory does not exist" do
      allow(Dir).to receive(:exist?).with("/nonexistent").and_return(false)
      expect(Dir).not_to receive(:chdir)
      handler.call({ "workspacePath" => "/nonexistent" })
    end
  end

  describe "client capabilities stored" do
    it "stores extension version on the server" do
      handler.call({ "extensionVersion" => "2.1.0" })
      expect(server.extension_version).to eq("2.1.0")
    end

    it "stores client capabilities on the server" do
      caps = { "supportsStreaming" => true, "supportsDiff" => false }
      handler.call({ "capabilities" => caps })
      expect(server.client_capabilities).to eq(caps)
    end

    it "defaults capabilities to empty hash when not provided" do
      handler.call({})
      expect(server.client_capabilities).to eq({})
    end
  end

  describe "error resilience" do
    it "returns 0 tools when Registry raises" do
      allow(RubynCode::Tools::Registry).to receive(:load_all!).and_raise(StandardError, "boom")
      result = handler.call({})
      expect(result["capabilities"]["tools"]).to eq(0)
    end

    it "returns 0 skills when Skills::Catalog raises" do
      allow(RubynCode::Skills::Catalog).to receive(:new).and_raise(StandardError, "boom")
      result = handler.call({})
      expect(result["capabilities"]["skills"]).to eq(0)
    end
  end
end
