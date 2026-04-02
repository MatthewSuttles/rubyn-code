# frozen_string_literal: true

module ToolHelpers
  def build_tool_result(tool_use_id, content, is_error: false)
    {
      type: "tool_result",
      tool_use_id: tool_use_id,
      content: content.to_s,
      is_error: is_error
    }
  end

  def create_test_file(dir, name, content = "test content")
    path = File.join(dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end
end

RSpec.configure do |config|
  config.include ToolHelpers
end
