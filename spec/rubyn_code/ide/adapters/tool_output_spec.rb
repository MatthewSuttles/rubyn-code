# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/ide/adapters/tool_output"
require "rubyn_code/ide/server"

RSpec.describe RubynCode::IDE::Adapters::ToolOutput do
  let(:server)  { RubynCode::IDE::Server.new }
  let(:notifications) { [] }

  before do
    allow(server).to receive(:notify) do |method, params|
      notifications << { "method" => method, "params" => params }
    end
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

    it "emits tool/use and tool/result notifications" do
      adapter.wrap_execution("read_file", { "path" => "/test.rb" }) do
        "file contents"
      end

      tool_use = notifications.find { |n| n["method"] == "tool/use" }
      expect(tool_use).not_to be_nil
      expect(tool_use["params"]["toolName"]).to eq("read_file")
      expect(tool_use["params"]["requiresApproval"]).to eq(false)

      tool_result = notifications.find { |n| n["method"] == "tool/result" }
      expect(tool_result).not_to be_nil
      expect(tool_result["params"]["success"]).to eq(true)
    end

    it "works with all read-only tool names" do
      %w[read_file glob grep git_status git_diff git_log git_commit
         memory_search web_fetch web_search].each do |tool|
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

    it "emits tool/use, then file notification, and blocks for acceptance" do
      allow(File).to receive(:exist?).and_return(false)

      accepted = nil
      writer = Thread.new do
        accepted = adapter.wrap_execution("write_file", { "path" => "/new.rb" }) do
          "written"
        end
      end
      sleep 0.2

      # Should have emitted tool/use and file/create
      tool_use = notifications.find { |n| n["method"] == "tool/use" }
      expect(tool_use).not_to be_nil

      file_notif = notifications.find { |n| n["method"] == "file/create" }
      expect(file_notif).not_to be_nil
      edit_id = file_notif["params"]["editId"]

      # Resolve the edit
      adapter.resolve_edit(edit_id, true)
      writer.join(2)

      expect(accepted).to eq("written")
    end

    it "emits file/edit when file already exists" do
      allow(File).to receive(:exist?).and_return(true)

      writer = Thread.new do
        adapter.wrap_execution("write_file", { "path" => "/existing.rb" }) { "updated" }
      end
      sleep 0.2

      file_edit = notifications.find { |n| n["method"] == "file/edit" }
      expect(file_edit).not_to be_nil

      # Clean up
      edit_id = file_edit["params"]["editId"]
      adapter.resolve_edit(edit_id, true)
      writer.join(2)
    end
  end

  describe "write_file in yolo mode" do
    let(:adapter) { described_class.new(server, yolo: true) }

    it "executes immediately without waiting for approval" do
      result = adapter.wrap_execution("write_file", { "path" => "/yolo.rb" }) do
        "written in yolo"
      end

      expect(result).to eq("written in yolo")
    end

    it "still emits tool/use and tool/result notifications" do
      adapter.wrap_execution("write_file", { "path" => "/yolo.rb" }) { "ok" }

      tool_use = notifications.find { |n| n["method"] == "tool/use" }
      expect(tool_use).not_to be_nil

      tool_result = notifications.find { |n| n["method"] == "tool/result" }
      expect(tool_result).not_to be_nil
      expect(tool_result["params"]["success"]).to eq(true)
    end
  end

  describe "edit_file approval flow" do
    let(:adapter) { described_class.new(server) }

    it "emits tool/use, waits, approved, then executes" do
      result_value = nil
      writer = Thread.new do
        result_value = adapter.wrap_execution("edit_file", { "path" => "/app.rb" }) do
          "edited content"
        end
      end
      sleep 0.2

      # Find the edit notification
      file_notif = notifications.find { |n| n["method"] == "file/edit" }
      expect(file_notif).not_to be_nil
      edit_id = file_notif["params"]["editId"]

      adapter.resolve_edit(edit_id, true)
      writer.join(2)

      expect(result_value).to eq("edited content")

      tool_result = notifications.select { |n| n["method"] == "tool/result" }.last
      expect(tool_result["params"]["success"]).to eq(true)
    end
  end

  describe "edit_file denial flow" do
    let(:adapter) { described_class.new(server) }

    it "returns denial message when edit is rejected" do
      result_value = nil
      writer = Thread.new do
        result_value = adapter.wrap_execution("edit_file", { "path" => "/app.rb" }) do
          "should not execute"
        end
      end
      sleep 0.2

      file_notif = notifications.find { |n| n["method"] == "file/edit" }
      edit_id = file_notif["params"]["editId"]

      adapter.resolve_edit(edit_id, false)
      writer.join(2)

      expect(result_value).to include("denied")

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
      expect(tool_use["params"]["toolName"]).to eq("bash")
      expect(tool_use["params"]["requiresApproval"]).to eq(true)
      expect(tool_use["params"]["args"]["command"]).to eq("ls -la")

      # Approve to unblock
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
      result = writer.value

      expect(result).to include("denied")
    end
  end

  describe "run_specs tool" do
    let(:adapter) { described_class.new(server) }

    it "executes with tool/use and tool/result notifications" do
      result = adapter.wrap_execution("run_specs", { "path" => "spec/" }) do
        "3 examples, 0 failures"
      end

      expect(result).to eq("3 examples, 0 failures")

      tool_use = notifications.find { |n| n["method"] == "tool/use" }
      expect(tool_use["params"]["toolName"]).to eq("run_specs")
      expect(tool_use["params"]["requiresApproval"]).to eq(false)

      tool_result = notifications.find { |n| n["method"] == "tool/result" }
      expect(tool_result["params"]["success"]).to eq(true)
    end
  end

  describe "approval timeout" do
    it "auto-denies after timeout expires" do
      # Create adapter with a very short timeout by stubbing the constant
      adapter = described_class.new(server)
      # Override APPROVAL_TIMEOUT via a short deadline
      stub_const("RubynCode::IDE::Adapters::ToolOutput::APPROVAL_TIMEOUT", 0.2)

      result = adapter.wrap_execution("bash", { "command" => "slow" }) do
        "executed"
      end

      # Should have auto-denied
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

    it "does nothing for unknown request_id" do
      # Should not raise
      expect { adapter.resolve_approval("unknown-id", true) }.not_to raise_error
    end
  end

  describe "#resolve_edit" do
    let(:adapter) { described_class.new(server) }

    it "signals the condition variable for a pending edit" do
      result = nil
      writer = Thread.new do
        result = adapter.wrap_execution("edit_file", { "path" => "/f.rb" }) { "edited" }
      end
      sleep 0.2

      file_notif = notifications.find { |n| n["method"] == "file/edit" }
      edit_id = file_notif["params"]["editId"]

      adapter.resolve_edit(edit_id, true)
      writer.join(2)

      expect(result).to eq("edited")
    end

    it "does nothing for unknown edit_id" do
      expect { adapter.resolve_edit("unknown-id", true) }.not_to raise_error
    end
  end

  describe "concurrent tool calls" do
    let(:adapter) { described_class.new(server) }

    it "handles multiple tools pending approval simultaneously" do
      results = {}
      ready_count = Queue.new

      # Override notify to also track when tool/use is emitted
      local_notifications = notifications
      allow(server).to receive(:notify) do |method, params|
        local_notifications << { "method" => method, "params" => params }
        ready_count.push(true) if method == "tool/use"
      end

      t1 = Thread.new do
        results[:first] = adapter.wrap_execution("bash", { "command" => "cmd1" }) { "result1" }
      end
      t2 = Thread.new do
        results[:second] = adapter.wrap_execution("bash", { "command" => "cmd2" }) { "result2" }
      end

      # Wait until both tool/use notifications have been emitted
      2.times { ready_count.pop }

      tool_uses = local_notifications.select { |n| n["method"] == "tool/use" }
      expect(tool_uses.size).to eq(2)

      # Approve both
      tool_uses.each do |tu|
        adapter.resolve_approval(tu["params"]["requestId"], true)
      end

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
