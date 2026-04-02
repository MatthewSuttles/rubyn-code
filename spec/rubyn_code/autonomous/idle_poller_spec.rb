# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Autonomous::IdlePoller do
  let(:mailbox) { instance_double("Mailbox") }
  let(:task_manager) { instance_double("TaskManager", db: db) }
  let(:db) { setup_test_db }

  describe "#poll!" do
    it "returns :resume when inbox has messages" do
      allow(mailbox).to receive(:pending_for).and_return(["msg"])
      allow(db).to receive(:query).and_return([])

      poller = described_class.new(
        mailbox: mailbox, task_manager: task_manager,
        agent_name: "agent", poll_interval: 0.05, idle_timeout: 1
      )

      expect(poller.poll!).to eq(:resume)
    end

    it "returns :shutdown when idle timeout expires" do
      allow(mailbox).to receive(:pending_for).and_return([])
      allow(db).to receive(:query).and_return([])

      poller = described_class.new(
        mailbox: mailbox, task_manager: task_manager,
        agent_name: "agent", poll_interval: 0.05, idle_timeout: 0.1
      )

      expect(poller.poll!).to eq(:shutdown)
    end

    it "returns :interrupted when interrupt! is called" do
      allow(mailbox).to receive(:pending_for).and_return([])
      allow(db).to receive(:query).and_return([])

      poller = described_class.new(
        mailbox: mailbox, task_manager: task_manager,
        agent_name: "agent", poll_interval: 0.1, idle_timeout: 5
      )

      poller.interrupt!
      expect(poller.poll!).to eq(:interrupted)
    end
  end
end
