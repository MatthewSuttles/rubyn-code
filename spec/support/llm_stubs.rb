# frozen_string_literal: true

module LLMStubs
  def stub_claude_text_response(text)
    response = RubynCode::LLM::Response.new(
      id: "msg_test_#{SecureRandom.hex(4)}",
      content: [RubynCode::LLM::TextBlock.new(text: text)],
      stop_reason: "end_turn",
      usage: RubynCode::LLM::Usage.new(input_tokens: 100, output_tokens: 50)
    )
    allow(llm_client).to receive(:chat).and_return(response)
    response
  end

  def stub_claude_tool_response(tool_name, tool_input, tool_id: nil)
    tid = tool_id || "toolu_test_#{SecureRandom.hex(4)}"
    response = RubynCode::LLM::Response.new(
      id: "msg_test_#{SecureRandom.hex(4)}",
      content: [
        RubynCode::LLM::ToolUseBlock.new(id: tid, name: tool_name, input: tool_input)
      ],
      stop_reason: "tool_use",
      usage: RubynCode::LLM::Usage.new(input_tokens: 100, output_tokens: 80)
    )
    allow(llm_client).to receive(:chat).and_return(response)
    response
  end

  def stub_claude_sequential_responses(*responses)
    allow(llm_client).to receive(:chat).and_return(*responses)
  end
end

RSpec.configure do |config|
  config.include LLMStubs
end
