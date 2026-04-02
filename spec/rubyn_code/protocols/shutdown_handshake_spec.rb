# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Protocols::ShutdownHandshake do
  let(:db) { setup_test_db }
  let(:mailbox) { RubynCode::Teams::Mailbox.new(db) }

  describe ".initiate" do
    it "sends a shutdown_request message" do
      # Respond immediately so initiate doesn't block
      described_class.respond(mailbox: mailbox, from: "worker", to: "coord")

      result = described_class.initiate(
        mailbox: mailbox, from: "coord", to: "worker", timeout: 1
      )
      expect(result).to eq(:acknowledged)
    end

    it "returns :timeout when no response arrives" do
      result = described_class.initiate(
        mailbox: mailbox, from: "coord", to: "worker", timeout: 0.3
      )
      expect(result).to eq(:timeout)
    end
  end

  describe ".respond" do
    it "sends a shutdown_response message" do
      msg_id = described_class.respond(
        mailbox: mailbox, from: "worker", to: "coord", approve: true
      )
      expect(msg_id).to be_a(String)

      messages = mailbox.read_inbox("coord")
      expect(messages.size).to eq(1)
      expect(messages.first[:message_type]).to eq("shutdown_response")
      expect(messages.first[:content]).to eq("shutdown_approved")
    end

    it "sends denial when approve is false" do
      described_class.respond(
        mailbox: mailbox, from: "worker", to: "coord", approve: false
      )
      messages = mailbox.read_inbox("coord")
      expect(messages.first[:content]).to eq("shutdown_denied")
    end
  end
end
