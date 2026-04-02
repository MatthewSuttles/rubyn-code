# frozen_string_literal: true

RSpec.describe RubynCode::Context::MicroCompact do
  def tool_use_msg(id, name)
    { role: "assistant", content: [{ type: "tool_use", id: id, name: name }] }
  end

  def tool_result_msg(id, content)
    { role: "user", content: [{ type: "tool_result", tool_use_id: id, content: content }] }
  end

  let(:long_content) { "x" * 200 }

  it "replaces old tool results with placeholders, keeping recent N" do
    messages = [
      tool_use_msg("t1", "bash"), tool_result_msg("t1", long_content),
      tool_use_msg("t2", "bash"), tool_result_msg("t2", long_content),
      tool_use_msg("t3", "grep"), tool_result_msg("t3", long_content),
      tool_use_msg("t4", "glob"), tool_result_msg("t4", long_content)
    ]

    compacted = described_class.call(messages, keep_recent: 2)

    expect(compacted).to eq(2)
    expect(messages[1][:content][0][:content]).to include("[Previous:")
    expect(messages[7][:content][0][:content]).to eq(long_content)
  end

  it "skips preserved tools" do
    messages = [
      tool_use_msg("t1", "read_file"), tool_result_msg("t1", long_content),
      tool_use_msg("t2", "bash"), tool_result_msg("t2", long_content),
      tool_use_msg("t3", "bash"), tool_result_msg("t3", long_content),
      tool_use_msg("t4", "bash"), tool_result_msg("t4", long_content)
    ]

    described_class.call(messages, keep_recent: 1, preserve_tools: ["read_file"])

    expect(messages[1][:content][0][:content]).to eq(long_content)
  end

  it "skips short content" do
    messages = [
      tool_use_msg("t1", "bash"), tool_result_msg("t1", "ok"),
      tool_use_msg("t2", "bash"), tool_result_msg("t2", long_content),
      tool_use_msg("t3", "bash"), tool_result_msg("t3", long_content)
    ]

    compacted = described_class.call(messages, keep_recent: 1)

    expect(compacted).to eq(1)
    expect(messages[1][:content][0][:content]).to eq("ok")
  end
end
