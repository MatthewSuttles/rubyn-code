  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::PlanInterviewCancelHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:session) { instance_double("RubynCode::Megaplan::InterviewSession", session_id: "sess-1") }
  let(:handler) { described_class.new(server) }

  it "drops the session for a known sessionId" do
    server.register_interview_session(session)
    handler.call({ "sessionId" => "sess-1" })
    expect(server.lookup_interview_session("sess-1")).to be_nil
  end

  it "is a no-op for an unknown sessionId" do
    expect { handler.call({ "sessionId" => "nope" }) }.not_to raise_error
  end

  it "returns nil so the server doesn't try to wrap it in a response" do
    server.register_interview_session(session)
    expect(handler.call({ "sessionId" => "sess-1" })).to be_nil
  end
end
