# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::Executor do
  let(:fake_tool) do
    Class.new(RubynCode::Tools::Base) do
      const_set(:TOOL_NAME, 'fake_exec_tool')
      const_set(:DESCRIPTION, 'Fake')
      const_set(:PARAMETERS, {}.freeze)
      const_set(:RISK_LEVEL, :read)

      def execute(**_params)
        'tool output'
      end
    end
  end

  before do
    RubynCode::Tools::Registry.reset!
    RubynCode::Tools::Registry.register(fake_tool)
  end

  after { RubynCode::Tools::Registry.reset! }

  describe '#execute' do
    it 'returns the tool output' do
      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('fake_exec_tool', {})
        expect(result).to eq('tool output')
      end
    end

    it 'handles unknown tools gracefully' do
      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('nonexistent', {})
        expect(result).to include('Tool error')
      end
    end

    it 'handles execution errors gracefully' do
      error_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'error_tool')
        const_set(:DESCRIPTION, 'Errors')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        def execute(**_params)
          raise StandardError, 'boom'
        end
      end
      RubynCode::Tools::Registry.register(error_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('error_tool', {})
        expect(result).to include('Unexpected error')
        expect(result).to include('boom')
      end
    end

    it 'filters params to only those accepted by the tool' do
      strict_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'strict_tool')
        const_set(:DESCRIPTION, 'Strict params')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        def execute(name:, count: 1)
          "#{name} x#{count}"
        end
      end
      RubynCode::Tools::Registry.register(strict_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('strict_tool', { 'name' => 'ruby', 'count' => 3, 'extra_junk' => true })
        expect(result).to eq('ruby x3')
      end
    end

    it 'truncates long output' do
      verbose_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'verbose_tool')
        const_set(:DESCRIPTION, 'Verbose')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        def execute(**_params)
          'x' * 100_000
        end
      end
      RubynCode::Tools::Registry.register(verbose_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('verbose_tool', {})
        expect(result.length).to be < 100_000
        expect(result).to include('truncated')
      end
    end

    it 'returns error message when tool raises PermissionDeniedError' do
      perm_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'perm_denied_tool')
        const_set(:DESCRIPTION, 'Permission denied')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        def execute(**_params)
          raise RubynCode::PermissionDeniedError, 'not allowed'
        end
      end
      RubynCode::Tools::Registry.register(perm_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('perm_denied_tool', {})
        expect(result).to include('Permission denied')
        expect(result).to include('not allowed')
      end
    end

    it 'returns error message when tool raises NotImplementedError' do
      not_impl_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'not_impl_tool')
        const_set(:DESCRIPTION, 'Not implemented')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        # inherits Base#execute which raises NotImplementedError
      end
      RubynCode::Tools::Registry.register(not_impl_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('not_impl_tool', {})
        expect(result).to include('Not implemented')
      end
    end

    it 'returns error message when tool raises generic RubynCode::Error' do
      generic_error_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'generic_error_tool')
        const_set(:DESCRIPTION, 'Generic error')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        def execute(**_params)
          raise RubynCode::Error, 'something went wrong'
        end
      end
      RubynCode::Tools::Registry.register(generic_error_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('generic_error_tool', {})
        expect(result).to eq('Error: something went wrong')
      end
    end

    it 'passes all symbolized params when tool accepts **kwargs' do
      splat_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'splat_tool')
        const_set(:DESCRIPTION, 'Splat')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        def execute(**params)
          params.keys.sort.join(',')
        end
      end
      RubynCode::Tools::Registry.register(splat_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        result = executor.execute('splat_tool', { 'alpha' => 1, 'beta' => 2 })
        expect(result).to eq('alpha,beta')
      end
    end
  end

  describe '#tool_definitions' do
    it 'delegates to Registry.tool_definitions' do
      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        definitions = executor.tool_definitions
        expect(definitions).to be_an(Array)

        names = definitions.map { |d| d[:name] }
        expect(names).to include('fake_exec_tool')
      end
    end
  end

  describe 'dependency injection' do
    it 'injects llm_client and on_status for spawn_agent tool' do
      agent_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'spawn_agent')
        const_set(:DESCRIPTION, 'Spawn agent')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :write)

        attr_accessor :llm_client, :on_status

        def execute(**_params)
          "client=#{!llm_client.nil?},status=#{!on_status.nil?}"
        end
      end
      RubynCode::Tools::Registry.register(agent_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        executor.llm_client = :fake_llm
        executor.on_agent_status = :fake_status

        result = executor.execute('spawn_agent', {})
        expect(result).to eq('client=true,status=true')
      end
    end

    it 'injects background_worker for background_run tool' do
      bg_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'background_run')
        const_set(:DESCRIPTION, 'Background run')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :write)

        attr_accessor :background_worker

        def execute(**_params)
          "worker=#{!background_worker.nil?}"
        end
      end
      RubynCode::Tools::Registry.register(bg_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        executor.background_worker = :fake_worker

        result = executor.execute('background_run', {})
        expect(result).to eq('worker=true')
      end
    end

    it 'injects llm_client, on_status, and db for spawn_teammate tool' do
      teammate_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'spawn_teammate')
        const_set(:DESCRIPTION, 'Spawn teammate')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :write)

        attr_accessor :llm_client, :on_status, :db

        def execute(**_params)
          "client=#{!llm_client.nil?},status=#{!on_status.nil?},db=#{!db.nil?}"
        end
      end
      RubynCode::Tools::Registry.register(teammate_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        executor.llm_client = :fake_llm
        executor.on_agent_status = :fake_status
        executor.db = :fake_db

        result = executor.execute('spawn_teammate', {})
        expect(result).to eq('client=true,status=true,db=true')
      end
    end

    it 'invalidates file cache entries when bash uses redirect operators' do
      bash_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'bash')
        const_set(:DESCRIPTION, 'Run bash')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :write)

        def execute(command: '')
          "ran: #{command}"
        end
      end
      RubynCode::Tools::Registry.register(bash_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        cache = executor.file_cache

        # Pre-populate a cache entry
        test_file = File.join(dir, 'test.txt')
        File.write(test_file, 'original')
        cache.read(test_file)
        expect(cache.cache.key?(test_file)).to be true

        # Execute a bash command that writes to the file via redirect
        executor.execute('bash', { 'command' => "echo hello > #{test_file}" })

        # The cache entry should have been invalidated
        expect(cache.cache.key?(test_file)).to be false
      end
    end

    it 'invalidates file cache entries when bash uses append redirect' do
      bash_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'bash')
        const_set(:DESCRIPTION, 'Run bash')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :write)

        def execute(command: '')
          "ran: #{command}"
        end
      end
      RubynCode::Tools::Registry.register(bash_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        cache = executor.file_cache

        test_file = File.join(dir, 'test.txt')
        File.write(test_file, 'original')
        cache.read(test_file)
        expect(cache.cache.key?(test_file)).to be true

        executor.execute('bash', { 'command' => "echo more >> #{test_file}" })
        expect(cache.cache.key?(test_file)).to be false
      end
    end

    it 'invalidates file cache entries when bash uses tee' do
      bash_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'bash')
        const_set(:DESCRIPTION, 'Run bash')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :write)

        def execute(command: '')
          "ran: #{command}"
        end
      end
      RubynCode::Tools::Registry.register(bash_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        cache = executor.file_cache

        test_file = File.join(dir, 'output.log')
        File.write(test_file, 'original')
        cache.read(test_file)
        expect(cache.cache.key?(test_file)).to be true

        executor.execute('bash', { 'command' => "echo data | tee #{test_file}" })
        expect(cache.cache.key?(test_file)).to be false
      end
    end

    it 'invalidates file cache entries when bash uses sed -i' do
      bash_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'bash')
        const_set(:DESCRIPTION, 'Run bash')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :write)

        def execute(command: '')
          "ran: #{command}"
        end
      end
      RubynCode::Tools::Registry.register(bash_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        cache = executor.file_cache

        test_file = File.join(dir, 'config.yml')
        File.write(test_file, 'original')
        cache.read(test_file)
        expect(cache.cache.key?(test_file)).to be true

        executor.execute('bash', { 'command' => "sed -i 's/old/new/' #{test_file}" })
        expect(cache.cache.key?(test_file)).to be false
      end
    end

    it 'does not inject dependencies for ordinary tools' do
      plain_tool = Class.new(RubynCode::Tools::Base) do
        const_set(:TOOL_NAME, 'plain_tool')
        const_set(:DESCRIPTION, 'Plain')
        const_set(:PARAMETERS, {}.freeze)
        const_set(:RISK_LEVEL, :read)

        attr_accessor :llm_client, :background_worker

        def execute(**_params)
          "client=#{llm_client.inspect},worker=#{background_worker.inspect}"
        end
      end
      RubynCode::Tools::Registry.register(plain_tool)

      with_temp_project do |dir|
        executor = described_class.new(project_root: dir)
        executor.llm_client = :fake_llm
        executor.background_worker = :fake_worker

        result = executor.execute('plain_tool', {})
        expect(result).to eq('client=nil,worker=nil')
      end
    end
  end
end
