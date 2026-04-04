# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Background::Worker do
  let(:notifier) { RubynCode::Background::Notifier.new }

  subject(:worker) do
    described_class.new(project_root: Dir.tmpdir, notifier: notifier)
  end

  describe "#run" do
    it "returns a job ID and completes the job" do
      job_id = worker.run('echo hello', timeout: 5)
      expect(job_id).to be_a(String)
      expect(job_id).not_to be_empty
      worker.shutdown!(timeout: 5)
      job = worker.status(job_id)
      expect(job.status).to eq(:completed)
      expect(job.result).to include('hello')
    end
  end

  describe "#status" do
    it "returns nil for unknown job ID" do
      expect(worker.status("nonexistent")).to be_nil
    end
  end

  describe "#drain_notifications" do
    it "returns completed job notifications" do
      worker.run("echo done", timeout: 5)
      worker.shutdown!(timeout: 5)
      notifications = worker.drain_notifications
      expect(notifications).not_to be_empty
      expect(notifications.first[:type]).to eq(:job_completed)
    end
  end

  describe "concurrent job cap" do
    it "raises when MAX_CONCURRENT jobs are running" do
      stubs = []
      RubynCode::Background::Worker::MAX_CONCURRENT.times do
        stubs << worker.run("sleep 10", timeout: 15)
      end

      expect { worker.run("echo overflow") }.to raise_error(RuntimeError, /Concurrency limit/)

      worker.shutdown!(timeout: 2)
    end
  end
end
