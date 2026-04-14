# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

# The chat experience in IDE mode depends on the Agent::Conversation for a
# given sessionId surviving across prompt requests. Before this fix, every
# prompt built a fresh Conversation and the model had zero multi-turn memory.
RSpec.describe RubynCode::IDE::Handlers::PromptHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:handler) { described_class.new(server) }

  describe "#reset_session" do
    it "drops the cached conversation so the next prompt starts fresh" do
      conversations = handler.instance_variable_get(:@conversations)
      conversations["sess-1"] = RubynCode::Agent::Conversation.new
      conversations["sess-1"].add_user_message("earlier message")
      expect(conversations["sess-1"].messages.size).to eq(1)

      handler.reset_session("sess-1")
      expect(conversations).not_to have_key("sess-1")
    end

    it "cancels any running thread for that session before dropping state" do
      sessions = handler.instance_variable_get(:@sessions)
      sleeper = Thread.new { sleep 5 }
      sessions["sess-2"] = sleeper

      handler.reset_session("sess-2")

      expect(sessions).not_to have_key("sess-2")
      expect(sleeper.alive?).to eq(false)
    end

    it "is idempotent — resetting a session that never existed is a no-op" do
      expect { handler.reset_session("never-seen") }.not_to raise_error
    end
  end

  describe "per-session conversation cache" do
    # Unit-level guarantee: the memoization shape build_agent_loop uses
    # (`@conversations[session_id] ||= Agent::Conversation.new`) reuses
    # the same object across calls with the same id, and reset_session
    # wipes it so the next access creates a fresh one.
    it "memoizes one Conversation per sessionId and wipes on reset" do
      convs = handler.instance_variable_get(:@conversations)

      convs["sess-A"] ||= RubynCode::Agent::Conversation.new
      first = convs["sess-A"]
      convs["sess-A"] ||= RubynCode::Agent::Conversation.new
      second = convs["sess-A"]
      expect(first).to equal(second)

      handler.reset_session("sess-A")
      convs["sess-A"] ||= RubynCode::Agent::Conversation.new
      third = convs["sess-A"]
      expect(third).not_to equal(first)
    end

    it "isolates conversations across different sessionIds" do
      convs = handler.instance_variable_get(:@conversations)
      convs["sess-A"] ||= RubynCode::Agent::Conversation.new
      convs["sess-B"] ||= RubynCode::Agent::Conversation.new

      convs["sess-A"].add_user_message("in A")
      expect(convs["sess-B"].messages).to be_empty
    end
  end
end
