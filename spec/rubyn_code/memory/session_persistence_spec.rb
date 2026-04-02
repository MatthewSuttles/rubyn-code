# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Memory::SessionPersistence do
  let(:db) { setup_test_db }
  subject(:persistence) { described_class.new(db) }

  let(:session_id) { "sess-001" }

  describe "#save_session and #load_session" do
    it "persists and retrieves a session" do
      persistence.save_session(
        session_id: session_id, project_path: "/proj",
        messages: [{ role: "user", content: "hello" }], title: "Test"
      )

      loaded = persistence.load_session(session_id)
      expect(loaded[:title]).to eq("Test")
      expect(loaded[:messages].size).to eq(1)
      expect(loaded[:project_path]).to eq("/proj")
    end

    it "returns nil for nonexistent session" do
      expect(persistence.load_session("nope")).to be_nil
    end
  end

  describe "#list_sessions" do
    it "returns summaries ordered by updated_at" do
      persistence.save_session(session_id: "s1", project_path: "/a", messages: [])
      persistence.save_session(session_id: "s2", project_path: "/a", messages: [])

      list = persistence.list_sessions(project_path: "/a")
      expect(list.size).to eq(2)
      expect(list.first[:id]).to be_a(String)
    end
  end

  describe "#delete_session" do
    it "removes the session permanently" do
      persistence.save_session(session_id: "del", project_path: "/x", messages: [])
      persistence.delete_session("del")
      expect(persistence.load_session("del")).to be_nil
    end
  end
end
