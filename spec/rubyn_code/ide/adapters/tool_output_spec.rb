# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/adapters/tool_output"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Adapters::ToolOutput do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:notifications) { [] }

  # Fake tool classes so the adapter's preview_content call doesn't try to
  # read real files off disk during specs.
  let(:fake_write_file) do
    Class.new do
      def initialize(project_root:); end

      def preview_content(path:, content:)
        { content: content, type: File.exist?(path) ? "modify" : "create" }
      end
    end
  end

  let(:fake_edit_file) do
    Class.new do
      def initialize(project_root:); end

      def preview_content(path:, old_text:, new_text:, replace_all: false)
        { content: "#{old_text} → #{new_text}#{replace_all ? ' (all)' : ''}", type: "modify" }
      end
    end
  end

  before do
    allow(server).to receive(:notify) do |method, params|
      notifications << { "method" => method, "params" => params }
    end

    allow(RubynCode::Tools::Registry).to receive(:get).and_call_original
    allow(RubynCode::Tools::Registry).to receive(:get).with("write_file").and_return(fake_write_file)
    allow(RubynCode::Tools::Registry).to receive(:get).with("edit_file").and_return(fake_edit_file)

    # Stub SecureRandom to produce unique but predictable IDs
    hex_counter = 0
    allow(SecureRandom).to receive(:hex) do |_n = nil|
      hex_counter += 1
      "deadbeef#{hex_counter}"
    end
  end

  describe "read-only tool" do
    let(:adapter) { described_class.new(server) }

    it "executes immediately without approval" do
      result = adapter.wrap_execution("read_file", { "path" => "/test.rb" }) do
        "file contents here"
      end

      expect(result).to eq("file contents here")
    end

    it "emits tool/use and tool/result notifications with `tool` key" do
      adapter.wrap_execution("read_file", { "path" => "/test.rb" }) do
        "file contents"
      end

      tool_use = notifications.find { |n| n["method"] == "tool/use" }
      expect(tool_use).not_to be_nil
      expect(tool_use["params"]["tool"]).to eq("read_file")
      expect(tool_use["params"]["requiresApproval"]).to eq(false)

      tool_result = notifications.find { |n| n["method"] == "tool/result" }
      expect(tool_result).not_to be_nil
      expect(tool_result["params"]["tool"]).to eq("read_file")
      expect(tool_result["params"]["success"]).to eq(true)
    end

    it "works with all read-only tool names" do
      %w[read_file glob grep git_status git_diff git_log git_commit
         memory_search web_fetch web_search run_specs].each do |tool|
        result = adapter.wrap_execution(tool, {}) { "ok" }
        expect(result).to eq("ok")
      end
    end

    it "emits error notification when tool raises" do
      expect do
        adapter.wrap_execution("read_file", {}) { raise StandardError, "no such file" }
      end.to raise_error(StandardError, "no such file")

      error_result = notifications.select { |n| n["method"] == "tool/result" }.last
      expect(error_result["params"]["success"]).to eq(false)
      expect(error_result["params"]["summary"]).to include("no such file")
    end
  end

  describe "write_file in normal mode" do
    let(:adapter) { described_class.new(server) }

    it "emits file/create for a new file, with editId and content" do
      allow(File).to receive(:exist?).and_return(false)

      writer = Thread.new do
        adapter.wrap_execution("write_file", { "path" => "/new.rb", "content" => "x = 1" }) do
          "written"
        end
      end
      sleep 0.2

      expect(notifications.find { |n| n["method"] == "tool/use" }).not_to be_nil

      file_notif = notifications.find { |n| n["method"] == "file/create" }
      expect(file_notif).not_to be_nil
      expect(file_notif["params"]["path"]).to eq("/new.rb")
      expect(file_notif["params"]["content"]).to eq("x = 1")
      expect(file_notif["params"]).not_to have_key("type") # file/create payload omits type

      adapter.resolve_edit(file_notif["params"]["editId"], true)
      expect(writer.value).to eq("written")
    end

    it "emits file/edit with type=modify when file already exists" do
      allow(File).to receive(:exist?).and_return(true)

      writer = Thread.new do
        adapter.wrap_execution("write_file", { "path" => "/existing.rb", "content" => "x = 2" }) do
          "updated"
        end
      end
      sleep 0.2

      file_edit = notifications.find { |n| n["method"] == "file/edit" }
      expect(file_edit).not_to be_nil
      expect(file_edit["params"]["type"]).to eq("modify")
      expect(file_edit["params"]["content"]).to eq("x = 2")

      adapter.resolve_edit(file_edit["params"]["editId"], true)
      writer.join(2)
    end
  end

  describe "write_file in yolo mode" do
    let(:adapter) { described_class.new(server, yolo: true) }

    it "executes immediately without waiting for approval" do
      allow(File).to receive(:exist?).and_return(false)

      result = adapter.wrap_execution("write_file", { "path" => "/yolo.rb", "content" => "y = 1" }) do
        "written in yolo"
      end

      expect(result).to eq("written in yolo")
    end

    it "still emits tool/use and tool/result notifications" do
      allow(File).to receive(:exist?).and_return(false)

      adapter.wrap_execution("write_file", { "path" => "/yolo.rb", "content" => "y = 1" }) { "ok" }

      expect(notifications.find { |n| n["method"] == "tool/use" }).not_to be_nil
      tool_result = notifications.find { |n| n["method"] == "tool/result" }
      expect(tool_result).not_to be_nil
      expect(tool_result["params"]["success"]).to eq(true)
    end
  end

  describe "edit_file approval flow" do
    let(:adapter) { described_class.new(server) }

    it "precomputes proposed content and emits file/edit with type=modify" do
      result_value = nil
      writer = Thread.new do
        args = { "path" => "/app.rb", "old_text" => "foo", "new_text" => "bar" }
        result_value = adapter.wrap_execution("edit_file", args) { "edited content" }
      end
      sleep 0.2

      file_notif = notifications.find { |n| n["method"] == "file/edit" }
      expect(file_notif).not_to be_nil
      expect(file_notif["params"]["type"]).to eq("modify")
      expect(file_notif["params"]["content"]).to eq("foo → bar")

      adapter.resolve_edit(file_notif["params"]["editId"], true)
      writer.join(2)

      expect(result_value).to eq("edited content")
      tool_result = notifications.select { |n| n["method"] == "tool/result" }.last
      expect(tool_result["params"]["success"]).to eq(true)
    end
  end

  describe "edit_file denial flow" do
    let(:adapter) { described_class.new(server) }

    it "returns denial message and does not run the block when rejected" do
      ran_block = false
      result_value = nil
      writer = Thread.new do
        args = { "path" => "/app.rb", "old_text" => "a", "new_text" => "b" }
        result_value = adapter.wrap_execution("edit_file", args) do
          ran_block = true
          "should not execute"
        end
      end
      sleep 0.2

      file_notif = notifications.find { |n| n["method"] == "file/edit" }
      adapter.resolve_edit(file_notif["params"]["editId"], false)
      writer.join(2)

      expect(ran_block).to eq(false)
      expect(result_value).to include("denied")

      tool_result = notifications.select { |n| n["method"] == "tool/result" }.last
      expect(tool_result["params"]["success"]).to eq(false)
    end
  end

  describe "edit_file preview error" do
    let(:adapter) { described_class.new(server) }

    it "emits a failure tool/result when preview_content raises and skips the block" do
      # Force preview to raise (e.g. old_text not found).
      allow_any_instance_of(fake_edit_file)
        .to receive(:preview_content).and_raise(RubynCode::Error, "old_text not found")

      ran_block = false
      args = { "path" => "/app.rb", "old_text" => "missing", "new_text" => "new" }
      result = adapter.wrap_execution("edit_file", args) do
        ran_block = true
        "edited"
      end

      expect(ran_block).to eq(false)
      expect(result).to include("old_text not found")

      # No file/edit notification should have been sent.
      expect(notifications.any? { |n| n["method"] == "file/edit" }).to eq(false)

      tool_result = notifications.select { |n| n["method"] == "tool/result" }.last
      expect(tool_result["params"]["success"]).to eq(false)
    end
  end

  describe "bash tool" do
    let(:adapter) { described_class.new(server) }

    it "emits tool/use with requiresApproval: true" do
      writer = Thread.new do
        adapter.wrap_execution("bash", { "command" => "ls -la" }) { "output" }
      end
      sleep 0.2

      tool_use = notifications.find { |n| n["method"] == "tool/use" }
      expect(tool_use).not_to be_nil
      expect(tool_use["params"]["tool"]).to eq("bash")
      expect(tool_use["params"]["requiresApproval"]).to eq(true)
      expect(tool_use["params"]["args"]["command"]).to eq("ls -la")

      request_id = tool_use["params"]["requestId"]
      adapter.resolve_approval(request_id, true)
      writer.join(2)
    end

    it "skips approval in yolo mode" do
      yolo_adapter = described_class.new(server, yolo: true)
      result = yolo_adapter.wrap_execution("bash", { "command" => "echo hi" }) { "hi" }
      expect(result).to eq("hi")
    end

    it "returns denial message when bash is denied" do
      writer = Thread.new do
        adapter.wrap_execution("bash", { "command" => "rm -rf /" }) { "executed" }
      end
      sleep 0.2

      tool_use = notifications.find { |n| n["method"] == "tool/use" }
      request_id = tool_use["params"]["requestId"]
      adapter.resolve_approval(request_id, false)

      expect(writer.value).to include("denied")
    end
  end

  describe "approval timeout" do
    it "auto-denies after timeout expires" do
      adapter = described_class.new(server)
      stub_const("RubynCode::IDE::Adapters::ToolOutput::APPROVAL_TIMEOUT", 0.2)

      result = adapter.wrap_execution("bash", { "command" => "slow" }) { "executed" }

      expect(result).to include("denied")
      tool_result = notifications.select { |n| n["method"] == "tool/result" }.last
      expect(tool_result["params"]["success"]).to eq(false)
    end
  end

  describe "#resolve_approval" do
    let(:adapter) { described_class.new(server) }

    it "signals the condition variable for a pending approval" do
      approved = nil
      writer = Thread.new do
        approved = adapter.wrap_execution("bash", { "command" => "test" }) { "done" }
      end
      sleep 0.2

      tool_use = notifications.find { |n| n["method"] == "tool/use" }
      request_id = tool_use["params"]["requestId"]

      adapter.resolve_approval(request_id, true)
      writer.join(2)

      expect(approved).to eq("done")
    end

    it "returns false for unknown request_id" do
      expect(adapter.resolve_approval("unknown-id", true)).to eq(false)
    end
  end

  describe "#resolve_edit" do
    let(:adapter) { described_class.new(server) }

    it "signals the condition variable for a pending edit" do
      result = nil
      writer = Thread.new do
        args = { "path" => "/f.rb", "old_text" => "a", "new_text" => "b" }
        result = adapter.wrap_execution("edit_file", args) { "edited" }
      end
      sleep 0.2

      file_notif = notifications.find { |n| n["method"] == "file/edit" }
      adapter.resolve_edit(file_notif["params"]["editId"], true)
      writer.join(2)

      expect(result).to eq("edited")
    end

    it "returns false for unknown edit_id" do
      expect(adapter.resolve_edit("unknown-id", true)).to eq(false)
    end
  end

  describe "concurrent tool calls" do
    let(:adapter) { described_class.new(server) }

    it "handles multiple tools pending approval simultaneously" do
      results = {}
      ready = Queue.new

      local_notifications = notifications
      allow(server).to receive(:notify) do |method, params|
        local_notifications << { "method" => method, "params" => params }
        ready.push(true) if method == "tool/use"
      end

      t1 = Thread.new do
        results[:first] = adapter.wrap_execution("bash", { "command" => "cmd1" }) { "result1" }
      end
      t2 = Thread.new do
        results[:second] = adapter.wrap_execution("bash", { "command" => "cmd2" }) { "result2" }
      end

      2.times { ready.pop }

      tool_uses = local_notifications.select { |n| n["method"] == "tool/use" }
      expect(tool_uses.size).to eq(2)

      tool_uses.each { |tu| adapter.resolve_approval(tu["params"]["requestId"], true) }

      t1.join(3)
      t2.join(3)

      expect(results[:first]).to eq("result1")
      expect(results[:second]).to eq("result2")
    end
  end

  describe "result summary truncation" do
    let(:adapter) { described_class.new(server) }

    it "truncates long results to 500 characters in notifications" do
      long_result = "x" * 1000
      adapter.wrap_execution("read_file", { "path" => "/big.rb" }) { long_result }

      tool_result = notifications.find { |n| n["method"] == "tool/result" }
      expect(tool_result["params"]["summary"].length).to eq(500)
    end
  end
end
