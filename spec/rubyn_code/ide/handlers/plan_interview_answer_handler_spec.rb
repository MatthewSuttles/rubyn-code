  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Handlers::PlanInterviewAnswerHandler do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:session) { instance_double("RubynCode::Megaplan::InterviewSession") }
  let(:handler) { described_class.new(server) }

  before do
    allow(session).to receive(:session_id).and_return("sess-1")
    server.register_interview_session(session)
  end

  it "emits the next question notification when the LLM has more to ask" do
    next_q = RubynCode::Megaplan::InterviewSession::Question.new(
      id: "q-2", text: "Next?", options: nil
    )
    allow(session).to receive(:answer).with("q-1", "user reply").and_return(next_q)
    notifications = []
    allow(server).to receive(:notify) { |method, params| notifications << [method, params] }

    handler.call({ "sessionId" => "sess-1", "questionId" => "q-1", "answer" => "user reply" })

    expect(notifications.first).to eq([
      "plan/interview/question",
      { "sessionId" => "sess-1", "questionId" => "q-2", "text" => "Next?", "options" => nil }
    ])
  end

  it "emits done and drops the session when the LLM returns a plan" do
    plan = { "slug" => "f", "feature" => "F", "phases" => [{ "name" => "x" }] }
    allow(session).to receive(:answer).and_return(plan)
    notifications = []
    allow(server).to receive(:notify) { |method, params| notifications << [method, params] }

    handler.call({ "sessionId" => "sess-1", "questionId" => "q-1", "answer" => "ok" })

    expect(notifications.first.first).to eq("plan/interview/done")
    expect(server.lookup_interview_session("sess-1")).to be_nil
  end

  it "raises JsonRpcError with SESSION_NOT_FOUND_CODE for an unknown sessionId" do
    expect {
      handler.call({ "sessionId" => "nope", "questionId" => "x", "answer" => "y" })
    }.to raise_error(RubynCode::IDE::Protocol::JsonRpcError) do |err|
      expect(err.code).to eq(described_class::SESSION_NOT_FOUND_CODE)
    end
  end

  it "raises JsonRpcError with INVALID_PARAMS when answer() raises InvalidAnswerError" do
    allow(session).to receive(:answer)
      .and_raise(RubynCode::Megaplan::InterviewSession::InvalidAnswerError, "stale id")
    expect {
      handler.call({ "sessionId" => "sess-1", "questionId" => "wrong", "answer" => "x" })
    }.to raise_error(RubynCode::IDE::Protocol::JsonRpcError) do |err|
      expect(err.code).to eq(RubynCode::IDE::Protocol::INVALID_PARAMS)
    end
  end

  it "emits plan/interview/error and drops the session on a malformed-LLM-response failure" do
    allow(session).to receive(:answer)
      .and_raise(RubynCode::Megaplan::InterviewSession::MalformedResponseError, "garbage")
    notifications = []
    allow(server).to receive(:notify) { |method, params| notifications << [method, params] }

    expect {
      handler.call({ "sessionId" => "sess-1", "questionId" => "q-1", "answer" => "x" })
    }.to raise_error(RubynCode::IDE::Protocol::JsonRpcError)

    expect(notifications.first).to eq([
      "plan/interview/error",
      { "sessionId" => "sess-1", "message" => "garbage" }
    ])
    expect(server.lookup_interview_session("sess-1")).to be_nil
  end
end
