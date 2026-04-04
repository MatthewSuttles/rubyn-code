# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Background::Worker do
  let(:notifier) { RubynCode::Background::Notifier.new }

  subject(:worker) do
    described_class.new(project_root: Dir.tmpdir, notifier: notifier)
  end

  describe '#run' do
    after { worker.shutdown!(timeout: 5) }

    it 'returns a job ID and completes the job' do
      job_id = worker.run('echo hello', timeout: 5)
      expect(job_id).to be_a(String)
      expect(job_id).not_to be_empty
      worker.shutdown!(timeout: 5)
      job = worker.status(job_id)
      expect(job.status).to eq(:completed)
      expect(job.result).to include('hello')
    end
  end

  describe '#status' do
    it 'returns nil for unknown job ID' do
      expect(worker.status('nonexistent')).to be_nil
    end
  end

  describe '#drain_notifications' do
    after { worker.shutdown!(timeout: 5) }

    it 'returns completed job notifications' do
      worker.run('echo done', timeout: 5)
      worker.shutdown!(timeout: 5)
      notifications = worker.drain_notifications
      expect(notifications).not_to be_empty
      expect(notifications.first[:type]).to eq(:job_completed)
    end
  end

  describe 'concurrent job cap' do
    it 'raises when MAX_CONCURRENT jobs are running' do
      # The concurrency check counts @jobs with :running status inside a mutex.
      # We can pre-fill the jobs hash to simulate MAX_CONCURRENT running jobs
      # without spawning any real processes — testing the guard, not the threads.
      jobs = worker.instance_variable_get(:@jobs)
      mutex = worker.instance_variable_get(:@mutex)

      mutex.synchronize do
        described_class::MAX_CONCURRENT.times do |i|
          jobs["fake-#{i}"] = RubynCode::Background::Job.new(
            id: "fake-#{i}",
            command: 'fake',
            status: :running,
            result: nil,
            started_at: Time.now,
            completed_at: nil
          )
        end
      end

      expect { worker.run('echo overflow') }
        .to raise_error(RuntimeError, /Concurrency limit/)
    end
  end
end
