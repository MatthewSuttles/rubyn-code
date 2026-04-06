# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe RubynCode::Tools::FileCache do
  subject(:cache) { described_class.new }

  let(:tempfile) { Tempfile.new(['cache_test', '.rb']) }
  let(:path) { tempfile.path }

  before do
    tempfile.write('original content')
    tempfile.flush
  end

  after do
    tempfile.close
    tempfile.unlink
  end

  describe '#read' do
    it 'returns content from disk on first read with source :disk' do
      result = cache.read(path)
      expect(result[:content]).to eq('original content')
      expect(result[:source]).to eq(:disk)
      expect(result[:tokens_saved]).to eq(0)
    end

    it 'returns content from cache on second read with source :cache' do
      cache.read(path)
      result = cache.read(path)
      expect(result[:content]).to eq('original content')
      expect(result[:source]).to eq(:cache)
      expect(result[:tokens_saved]).to be_positive
    end

    it 're-reads from disk after file modification' do
      cache.read(path)

      # Ensure mtime changes by sleeping briefly then writing
      sleep 0.05
      File.write(path, 'updated content')

      result = cache.read(path)
      expect(result[:content]).to eq('updated content')
      expect(result[:source]).to eq(:disk)
    end

    it 'raises Errno::ENOENT when file does not exist' do
      expect { cache.read('/nonexistent/path/to/file.rb') }
        .to raise_error(Errno::ENOENT)
    end

    context 'with multiple files' do
      let(:tempfile2) { Tempfile.new(['cache_test2', '.rb']) }

      before do
        tempfile2.write('second file content')
        tempfile2.flush
      end

      after do
        tempfile2.close
        tempfile2.unlink
      end

      it 'tracks files independently' do
        cache.read(path)
        cache.read(tempfile2.path)

        result1 = cache.read(path)
        result2 = cache.read(tempfile2.path)

        expect(result1[:source]).to eq(:cache)
        expect(result2[:source]).to eq(:cache)
        expect(result1[:content]).to eq('original content')
        expect(result2[:content]).to eq('second file content')
      end
    end
  end

  describe '#invalidate' do
    it 'removes the entry from the cache' do
      cache.read(path)
      cache.invalidate(path)

      result = cache.read(path)
      expect(result[:source]).to eq(:disk)
    end
  end

  describe '#on_write' do
    it 'invalidates the path like a write hook' do
      cache.read(path)
      cache.on_write(path)

      result = cache.read(path)
      expect(result[:source]).to eq(:disk)
    end
  end

  describe '#cached?' do
    it 'returns false for a path not in the cache' do
      expect(cache.cached?(path)).to be false
    end

    it 'returns true for a fresh cached entry' do
      cache.read(path)
      expect(cache.cached?(path)).to be true
    end

    it 'returns false after the file has been modified' do
      cache.read(path)
      sleep 0.05
      File.write(path, 'changed')
      expect(cache.cached?(path)).to be false
    end

    it 'returns false and cleans up when file has been deleted' do
      cache.read(path)
      tempfile.close
      tempfile.unlink

      expect(cache.cached?(path)).to be false
      expect(cache.cache).not_to have_key(path)
    end
  end

  describe '#clear!' do
    it 'empties the entire cache' do
      cache.read(path)
      cache.clear!

      expect(cache.cache).to be_empty
    end
  end

  describe '#stats' do
    it 'returns zeroes for an empty cache' do
      stats = cache.stats
      expect(stats[:entries]).to eq(0)
      expect(stats[:total_reads]).to eq(0)
      expect(stats[:cache_hits]).to eq(0)
      expect(stats[:hit_rate]).to eq(0.0)
      expect(stats[:tokens_saved]).to eq(0)
    end

    it 'returns correct statistics after reads and cache hits' do
      cache.read(path)       # disk read
      cache.read(path)       # cache hit
      cache.read(path)       # cache hit

      stats = cache.stats
      expect(stats[:entries]).to eq(1)
      expect(stats[:total_reads]).to eq(1)
      expect(stats[:cache_hits]).to eq(2)
      expect(stats[:hit_rate]).to be > 0.0
      expect(stats[:tokens_saved]).to be_positive
    end

    it 'computes hit_rate correctly' do
      cache.read(path)   # 1 read
      cache.read(path)   # 1 hit
      cache.read(path)   # 2 hits

      stats = cache.stats
      # hit_rate = total_hits / (total_reads + total_hits) = 2 / (1 + 2) = 0.667
      expect(stats[:hit_rate]).to eq(0.667)
    end
  end
end
