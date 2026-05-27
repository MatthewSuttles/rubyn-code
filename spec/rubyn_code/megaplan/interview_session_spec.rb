  # frozen_string_literal: true

require "spec_helper"
require "rubyn_code/megaplan/interview_session"
require "rubyn_code/megaplan/plan_proposer"

RSpec.describe RubynCode::Megaplan::InterviewSession do
  let(:llm) { instance_double("RubynCode::LLM::Client") }
  let(:executor) do
    instance_double("RubynCode::Tools::Executor",
                    tool_definitions: [
                      { name: "read_file", description: "x", input_schema: {} },
                      { name: "grep", description: "y", input_schema: {} },
                      { name: "glob", description: "z", input_schema: {} },
                      { name: "git_status", description: "g", input_schema: {} },
                      { name: "git_diff", description: "g", input_schema: {} },
                      { name: "git_log", description: "g", input_schema: {} },
                      { name: "edit_file", description: "WRITE", input_schema: {} },
                      { name: "bash", description: "EXEC", input_schema: {} }
                    ])
  end
  let(:session) { described_class.new(llm_client: llm, executor: executor) }

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

  # The interview loop's response-shape branching uses .tool_calls and
  # .content if present; passing a String returns that String as the
  # "final text" of the turn. These helpers cover both modes.
  def text_response(text)
    text
  end

  def tool_use_response(name:, input:, id: "tu_1")
    instance_double(
      "RubynCode::LLM::Response",
      tool_calls: [
        RubynCode::LLM::ToolUseBlock.new(id: id, name: name, input: input)
      ],
      content: [
        RubynCode::LLM::ToolUseBlock.new(id: id, name: name, input: input)
      ],
      text: ""
    )
  end

  describe "#start" do
    it "returns the first Question when the LLM emits a question" do
      allow(llm).to receive(:chat).and_return(text_response(question_json("What's the end state?", ["A", "B", "C"])))
      q = session.start
      expect(q).to be_a(described_class::Question)
      expect(q.text).to eq("What's the end state?")
      expect(q.options).to eq(["A", "B", "C"])
    end

    it "returns a plan Hash when the LLM jumps straight to the plan" do
      allow(llm).to receive(:chat).and_return(text_response(plan_json))
      outcome = session.start
      expect(outcome).to eq(plan_payload)
    end

    it "treats an empty options array as an open question (options nil)" do
      allow(llm).to receive(:chat).and_return(text_response(question_json("Describe scope", [])))
      q = session.start
      expect(q.options).to be_nil
      expect(q.open?).to be(true)
    end

    it "raises MalformedResponseError when the LLM returns invalid JSON" do
      allow(llm).to receive(:chat).and_return(text_response("I'll happily help you plan that!"))
      expect { session.start }.to raise_error(described_class::MalformedResponseError, /not valid JSON/)
    end

    it "raises MalformedResponseError when the JSON is neither a question nor a plan" do
      allow(llm).to receive(:chat).and_return(text_response(JSON.generate({ "foo" => "bar" })))
      expect { session.start }.to raise_error(described_class::MalformedResponseError, /neither/)
    end

    it "raises InvalidProposalError when the LLM emits a plan with empty phases" do
      bad_plan = plan_payload.merge("phases" => [])
      allow(llm).to receive(:chat).and_return(text_response(plan_json(bad_plan)))
      expect { session.start }.to raise_error(RubynCode::Megaplan::PlanProposer::InvalidProposalError, /empty/)
    end
  end

  describe "#answer" do
    it "feeds the user answer to the LLM and returns the next Question" do
      allow(llm).to receive(:chat).and_return(
        text_response(question_json("First Q?", ["A"])),
        text_response(question_json("Second Q?", ["B"]))
      )
      first = session.start
      second = session.answer(first.id, "A")
      expect(second).to be_a(described_class::Question)
      expect(second.text).to eq("Second Q?")
    end

    it "returns the plan when the LLM is done interviewing" do
      allow(llm).to receive(:chat).and_return(
        text_response(question_json("Final Q?", ["A"])),
        text_response(plan_json)
      )
      first = session.start
      result = session.answer(first.id, "A")
      expect(result).to eq(plan_payload)
    end

    it "raises InvalidAnswerError when called with a stale questionId" do
      allow(llm).to receive(:chat).and_return(text_response(question_json("Q1", ["A"])))
      first = session.start
      expect { session.answer("not-the-id", "anything") }
        .to raise_error(described_class::InvalidAnswerError, /wrong question id/)
    end

    it "raises InvalidAnswerError when called before any question was asked" do
      allow(llm).to receive(:chat).and_return(text_response(plan_json))
      session.start
      expect { session.answer("x", "y") }
        .to raise_error(described_class::InvalidAnswerError, /no question/)
    end
  end

  it "tolerates ```json fences around the LLM response" do
    fenced = "```json\n#{question_json("Q", ["A"])}\n```"
    allow(llm).to receive(:chat).and_return(text_response(fenced))
    expect(session.start.text).to eq("Q")
  end

  describe "read-only tool palette" do
    it "filters Tools::Executor.tool_definitions down to the INTERVIEW_TOOLS whitelist" do
      captured = nil
      allow(llm).to receive(:chat) do |kwargs|
        captured = kwargs[:tools]
        text_response(question_json("Q", ["A"]))
      end
      session.start
      names = captured.map { |t| t[:name] }
      expect(names).to match_array(described_class::INTERVIEW_TOOLS)
      expect(names).not_to include("edit_file")
      expect(names).not_to include("bash")
    end

    it "executes a tool_use response and continues the loop with the result" do
      allow(executor).to receive(:execute).with("read_file", { "path" => "app/models/user.rb" })
                                          .and_return("class User < ApplicationRecord\nend\n")

      allow(llm).to receive(:chat).and_return(
        tool_use_response(name: "read_file", input: { "path" => "app/models/user.rb" }),
        text_response(question_json("Does the User already have a deleted_at column?", ["yes", "no"]))
      )

      q = session.start
      expect(q.text).to include("deleted_at")
      expect(executor).to have_received(:execute).with("read_file", { "path" => "app/models/user.rb" })
    end

    it "raises MalformedResponseError when the tool loop blows the MAX_TOOL_TURNS cap" do
      tool_loop = tool_use_response(name: "read_file", input: { "path" => "Gemfile" })
      allow(llm).to receive(:chat).and_return(tool_loop)
      allow(executor).to receive(:execute).and_return("ok")
      expect { session.start }.to raise_error(described_class::MalformedResponseError, /loop exceeded/)
    end

    it "INTERVIEW_TOOLS is read-only — never includes write/exec tools" do
      forbidden = %w[edit_file write_file bash bundle_add bundle_install db_migrate git_commit
                     rails_generate memory_write spawn_agent spawn_teammate task background_run]
      expect(described_class::INTERVIEW_TOOLS & forbidden).to be_empty
    end
  end

  describe "system prompt" do
    it "embeds the megaplan skill body so the LLM sees the full workflow guidance" do
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include("Vertical slices, not horizontal")
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include("Ask one question at a time")
    end

    it "appends an output contract that scopes the tool palette to read-only and demands JSON" do
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include("READ-ONLY")
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include('"question"')
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include('"plan"')
      expect(described_class::DEFAULT_INTERVIEW_PROMPT).to include("Never produce free-form coding-agent output")
    end
  end
end
