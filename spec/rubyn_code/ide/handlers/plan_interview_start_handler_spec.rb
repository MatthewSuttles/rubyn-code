  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::PlanInterviewStartHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:session) { instance_double("RubynCode::Megaplan::InterviewSession") }
  let(:factory) { ->(workspace_path:) { session } }
  let(:handler) { described_class.new(server, factory: factory) }

  before do
    allow(session).to receive(:session_id).and_return("sess-123")
  end

  it "registers the session, emits a question notification, and returns sessionId" do
    question = RubynCode::Megaplan::InterviewSession::Question.new(
      id: "q-1", text: "What's the goal?", options: ["A", "B"]
    )
    allow(session).to receive(:start).and_return(question)
    notifications = []
    allow(server).to receive(:notify) { |method, params| notifications << [method, params] }

    result = handler.call({})

    expect(result).to eq("sessionId" => "sess-123")
    expect(server.lookup_interview_session("sess-123")).to be(session)
    expect(notifications).to eq([
      ["plan/interview/question", {
        "sessionId" => "sess-123",
        "questionId" => "q-1",
        "text" => "What's the goal?",
        "options" => ["A", "B"]
      }]
    ])
  end

  it "emits a done notification and drops the session when start returns a plan" do
    plan = { "slug" => "f", "feature" => "F", "phases" => [{ "name" => "a" }] }
    allow(session).to receive(:start).and_return(plan)
    notifications = []
    allow(server).to receive(:notify) { |method, params| notifications << [method, params] }

    handler.call({})

    expect(notifications.first).to eq([
      "plan/interview/done",
      { "sessionId" => "sess-123", "plan" => plan }
    ])
    expect(server.lookup_interview_session("sess-123")).to be_nil
  end

  it "raises JsonRpcError when InterviewSession errors out" do
    allow(session).to receive(:start)
      .and_raise(RubynCode::Megaplan::InterviewSession::MalformedResponseError, "bad json")
    expect { handler.call({}) }.to raise_error(RubynCode::IDE::Protocol::JsonRpcError, /bad json/)
  end
end
