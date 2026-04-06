# frozen_string_literal: true

require 'tmpdir'

RSpec.describe RubynCode::Context::ContextBudget do
  subject(:budget) { described_class.new(budget: token_budget) }

  let(:token_budget) { 4000 }

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  def write_file(name, content)
    path = File.join(@tmpdir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def tokens_for(text)
    (text.bytesize.to_f / described_class::CHARS_PER_TOKEN).ceil
  end

  describe '#load_for' do
    context 'with primary file only' do
      it 'loads the primary file fully' do
        path = write_file('primary.rb', 'class Foo; end')

        results = budget.load_for(path)

        expect(results.length).to eq(1)
        expect(results.first[:file]).to eq(path)
        expect(results.first[:content]).to eq('class Foo; end')
        expect(results.first[:mode]).to eq(:full)
      end

      it 'tracks the primary file in loaded_files' do
        path = write_file('primary.rb', 'class Foo; end')

        budget.load_for(path)

        expect(budget.loaded_files).to eq([path])
      end

      it 'tracks tokens used for the primary file' do
        content = 'class Foo; end'
        path = write_file('primary.rb', content)

        budget.load_for(path)

        expect(budget.tokens_used).to eq(tokens_for(content))
      end
    end

    context 'with related files that fit in budget' do
      it 'loads related files fully when they fit' do
        primary = write_file('primary.rb', 'class Foo; end')
        related = write_file('spec_foo.rb', 'describe Foo')

        results = budget.load_for(primary, related_files: [related])

        expect(results.length).to eq(2)
        expect(results.last[:file]).to eq(related)
        expect(results.last[:mode]).to eq(:full)
      end
    end

    context 'when related files exceed budget' do
      let(:token_budget) { 20 }

      it 'falls back to signatures for files that do not fit fully' do
        primary = write_file('primary.rb', 'x = 1')
        large_related = write_file('service_big.rb', <<~RUBY)
          class BigService
            def perform(arg)
              # lots of implementation
              # that takes up space
              # and more space here
              # and even more space
              arg.to_s * 100
            end
          end
        RUBY

        results = budget.load_for(primary, related_files: [large_related])

        sig_result = results.find { |r| r[:file] == large_related }
        if sig_result
          expect(sig_result[:mode]).to eq(:signatures)
          expect(budget.signature_files).to include(large_related)
        end
      end
    end

    context 'with missing or empty files' do
      it 'returns empty results for a nonexistent primary file' do
        results = budget.load_for('/nonexistent/file.rb')

        expect(results).to be_empty
      end

      it 'skips nonexistent related files gracefully' do
        primary = write_file('primary.rb', 'class Foo; end')

        results = budget.load_for(primary, related_files: ['/nonexistent/related.rb'])

        expect(results.length).to eq(1)
        expect(results.first[:file]).to eq(primary)
      end

      it 'handles empty files by still loading them' do
        primary = write_file('primary.rb', '')
        results = budget.load_for(primary)

        expect(results.length).to eq(1)
        expect(results.first[:content]).to eq('')
        expect(results.first[:mode]).to eq(:full)
      end
    end

    context 'with a budget of 0' do
      let(:token_budget) { 0 }

      it 'only loads the primary file' do
        primary = write_file('primary.rb', 'x')
        related = write_file('spec_foo.rb', 'y')

        results = budget.load_for(primary, related_files: [related])

        expect(results.length).to eq(1)
        expect(results.first[:file]).to eq(primary)
      end
    end

    context 'priority ordering' do
      let(:token_budget) { 100_000 }

      it 'loads spec files before factories before services before models before controllers' do
        primary = write_file('primary.rb', 'x')
        controller = write_file('foo_controller.rb', 'c')
        model = write_file('foo_model.rb', 'm')
        service = write_file('foo_service.rb', 's')
        factory = write_file('foo_factory.rb', 'f')
        spec = write_file('foo_spec.rb', 't')

        results = budget.load_for(
          primary,
          related_files: [controller, model, service, factory, spec]
        )

        related_files = results[1..].map { |r| r[:file] }
        expect(related_files).to eq([spec, factory, service, model, controller])
      end
    end
  end

  describe '#extract_signatures' do
    it 'returns method and class definitions without bodies' do
      content = <<~RUBY
        class User
          attr_reader :name

          def initialize(name)
            @name = name
          end

          def greet
            "Hello, \#{@name}"
          end
        end
      RUBY

      sigs = budget.extract_signatures(content)

      expect(sigs).to include('class User')
      expect(sigs).to include('attr_reader :name')
      expect(sigs).to include('def initialize(name)')
      expect(sigs).to include('def greet')
      expect(sigs).not_to include('@name = name')
      expect(sigs).not_to include('Hello')
    end

    it 'includes has_many, belongs_to, validates, scope, and delegate lines' do
      content = <<~RUBY
        class Post < ApplicationRecord
          has_many :comments
          belongs_to :author
          validates :title, presence: true
          scope :published, -> { where(published: true) }
          delegate :name, to: :author

          def publish!
            update!(published: true)
          end
        end
      RUBY

      sigs = budget.extract_signatures(content)

      expect(sigs).to include('has_many :comments')
      expect(sigs).to include('belongs_to :author')
      expect(sigs).to include('validates :title')
      expect(sigs).to include('scope :published')
      expect(sigs).to include('delegate :name')
      expect(sigs).not_to include('update!')
    end

    it 'includes include and extend lines' do
      content = <<~RUBY
        module Concerns
          include ActiveModel::Validations
          extend ClassMethods
        end
      RUBY

      sigs = budget.extract_signatures(content)

      expect(sigs).to include('include ActiveModel::Validations')
      expect(sigs).to include('extend ClassMethods')
    end
  end

  describe '#stats' do
    it 'returns budget utilization statistics' do
      primary = write_file('primary.rb', 'class Foo; end')

      budget.load_for(primary)

      result = budget.stats
      expect(result[:budget]).to eq(token_budget)
      expect(result[:tokens_used]).to be_positive
      expect(result[:utilization]).to be_a(Float)
      expect(result[:full_files]).to eq(1)
      expect(result[:signature_files]).to eq(0)
    end

    it 'returns zero utilization when budget is zero' do
      zero_budget = described_class.new(budget: 0)

      result = zero_budget.stats
      expect(result[:utilization]).to eq(0.0)
    end
  end
end
