  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/megaplan/interview_session"
require "rubyn_code/megaplan/plan_proposer"

RSpec.describe RubynCode::Megaplan::InterviewSession do
  let(:llm) { instance_double("RubynCode::LLM::Client") }
  let(:session) { described_class.new(llm_client: llm) }

  def question_json(text, options = nil)
    JSON.generate({ "question" => { "text" => text, "options" => options } })
  end

  let(:plan_payload) do
    {
      "slug" => "feature",
      "feature" => "Add a feature",
      "phases" => [
        {
          "number" => 1,
          "slug" => "schema",
          "name" => "Schema",
          "summary" => "Add column",
          "requirements_md" => "# req",
          "design_md" => "# design",
          "tasks_md" => "# tasks"
        }
      ]
    }
  end

  def plan_json(payload = plan_payload)
    JSON.generate({ "plan" => payload })
  end

  describe "#start" do
    it "returns the first Question when the LLM emits a question" do
      allow(llm).to receive(:chat).and_return(question_json("What's the end state?", ["A", "B", "C"]))
      q = session.start
      expect(q).to be_a(described_class::Question)
      expect(q.text).to eq("What's the end state?")
      expect(q.options).to eq(["A", "B", "C"])
    end

    it "returns a plan Hash when the LLM jumps straight to the plan" do
      allow(llm).to receive(:chat).and_return(plan_json)
      outcome = session.start
      expect(outcome).to eq(plan_payload)
    end

    it "treats an empty options array as an open question (options nil)" do
      allow(llm).to receive(:chat).and_return(question_json("Describe scope", []))
      q = session.start
      expect(q.options).to be_nil
      expect(q.open?).to be(true)
    end

    it "raises MalformedResponseError when the LLM returns invalid JSON" do
      allow(llm).to receive(:chat).and_return("I'll happily help you plan that!")
      expect { session.start }.to raise_error(described_class::MalformedResponseError, /not valid JSON/)
    end

    it "raises MalformedResponseError when the JSON is neither a question nor a plan" do
      allow(llm).to receive(:chat).and_return(JSON.generate({ "foo" => "bar" }))
      expect { session.start }.to raise_error(described_class::MalformedResponseError, /neither/)
    end

    it "raises InvalidProposalError when the LLM emits a plan with empty phases" do
      bad_plan = plan_payload.merge("phases" => [])
      allow(llm).to receive(:chat).and_return(plan_json(bad_plan))
      expect { session.start }.to raise_error(RubynCode::Megaplan::PlanProposer::InvalidProposalError, /empty/)
    end
  end

  describe "#answer" do
    it "feeds the user answer to the LLM and returns the next Question" do
      allow(llm).to receive(:chat).and_return(
        question_json("First Q?", ["A"]),
        question_json("Second Q?", ["B"])
      )
      first = session.start
      second = session.answer(first.id, "A")
      expect(second).to be_a(described_class::Question)
      expect(second.text).to eq("Second Q?")
    end

    it "returns the plan when the LLM is done interviewing" do
      allow(llm).to receive(:chat).and_return(
        question_json("Final Q?", ["A"]),
        plan_json
      )
      first = session.start
      result = session.answer(first.id, "A")
      expect(result).to eq(plan_payload)
    end

    it "raises InvalidAnswerError when called with a stale questionId" do
      allow(llm).to receive(:chat).and_return(question_json("Q1", ["A"]))
      first = session.start
      expect { session.answer("not-the-id", "anything") }
        .to raise_error(described_class::InvalidAnswerError, /wrong question id/)
    end

    it "raises InvalidAnswerError when called before any question was asked" do
      allow(llm).to receive(:chat).and_return(plan_json)
      session.start  # ends with a plan, so no @last_question
      expect { session.answer("x", "y") }
        .to raise_error(described_class::InvalidAnswerError, /no question/)
    end
  end

  it "tolerates ```json fences around the LLM response" do
    fenced = "```json\n#{question_json("Q", ["A"])}\n```"
    allow(llm).to receive(:chat).and_return(fenced)
    expect(session.start.text).to eq("Q")
  end

  describe "system prompt" do
    it "embeds the megaplan skill body so the LLM sees the full workflow guidance" do
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include("Vertical slices, not horizontal")
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include("Ask one question at a time")
    end

    it "appends a strict JSON-output contract that disables coding-agent behavior" do
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include("You do NOT have tools available")
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include('"question"')
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include('"plan"')
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include("Never produce free-form coding-agent output")
    end
  end

  it "passes tools: nil to the LLM so it can't fall back into agent mode" do
    allow(llm).to receive(:chat).and_return(question_json("Q", ["A"]))
    session.start
    expect(llm).to have_received(:chat).with(hash_including(tools: nil))
  end
end
