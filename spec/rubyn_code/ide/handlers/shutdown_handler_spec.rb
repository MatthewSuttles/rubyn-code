# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::ShutdownHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  describe "returns shutdown" do
    it "returns { shutdown: true }" do
      result = handler.call({})
      expect(result["shutdown"]).to eq(true)
    end
  end

  describe "stops server" do
    it "calls server.stop!" do
      expect(server).to receive(:stop!)
      handler.call({})
    end
  end

  describe "saves session" do
    context "when SessionPersistence is defined" do
      before do
        stub_const("RubynCode::Memory::SessionPersistence", Class.new)
      end

      it "calls save on the session persistence object" do
        persistence = double("SessionPersistence")
        server.session_persistence = persistence
        expect(persistence).to receive(:save)

        handler.call({})
      end

      it "handles nil session_persistence gracefully" do
        server.session_persistence = nil
        expect { handler.call({}) }.not_to raise_error
      end

      it "handles save errors gracefully" do
        persistence = double("SessionPersistence")
        server.session_persistence = persistence
        allow(persistence).to receive(:save).and_raise(StandardError, "disk full")

        expect { handler.call({}) }.not_to raise_error
      end
    end

    context "when SessionPersistence is not defined" do
      it "does not attempt to save" do
        # SessionPersistence should not be defined in test environment (unless stubbed)
        expect { handler.call({}) }.not_to raise_error
      end
    end
  end
end
