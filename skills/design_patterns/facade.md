# Design Pattern: Facade

## Pattern

Provide a simplified interface to a complex subsystem. The facade hides the complexity of multiple classes, APIs, or steps behind a single method call. In Rails, service objects often act as facades over multi-step operations.

```ruby
# The subsystem is complex — embedding client, chunker, database, change detection
# The facade makes it one call

class Codebase::IndexFacade
  def initialize(
    embedding_client: Rails.application.config.x.embedding_client,
    chunker: Codebase::Chunker.new,
    change_detector: Codebase::ChangeDetector.new
  )
    @embedding_client = embedding_client
    @chunker = chunker
    @change_detector = change_detector
  end

  # One method hides 5 subsystem interactions
  def index_project(project, files)
    changed_files = @change_detector.filter_changed(project, files)
    return { indexed: 0, skipped: files.size } if changed_files.empty?

    changed_files.each_slice(10) do |batch|
      chunks = batch.flat_map { |path, content| @chunker.split(path, content) }
      vectors = @embedding_client.embed(chunks.map(&:text))

      chunks.zip(vectors).each do |chunk, vector|
        project.code_embeddings.upsert(
          {
            file_path: chunk.path,
            chunk_content: chunk.text,
            chunk_type: chunk.type,
            embedding: vector,
            file_hash: chunk.file_hash,
            last_embedded_at: Time.current
          },
          unique_by: [:project_id, :file_path, :chunk_type, :chunk_content]
        )
      end
    end

    project.update!(last_indexed_at: Time.current)
    { indexed: changed_files.size, skipped: files.size - changed_files.size }
  end
end

# Caller doesn't know about chunkers, change detectors, or embedding clients
result = Codebase::IndexFacade.new.index_project(project, files)
puts "Indexed #{result[:indexed]} files, skipped #{result[:skipped]}"
```

Another example — wrapping a multi-step onboarding process:

```ruby
class Onboarding::Facade
  def self.call(registration_params)
    new(registration_params).call
  end

  def initialize(params)
    @params = params
  end

  def call
    user = create_user
    project = create_default_project(user)
    api_key = generate_api_key(user)
    seed_credits(user)
    send_welcome(user)

    Result.new(success: true, user: user, project: project, api_key: api_key)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success: false, error: e.record.errors.full_messages.join(", "))
  end

  private

  def create_user
    User.create!(
      email: @params[:email],
      password: @params[:password],
      name: @params[:name]
    )
  end

  def create_default_project(user)
    project = Project.create!(name: "My First Project")
    ProjectMembership.create!(user: user, project: project, role: :owner)
    project
  end

  def generate_api_key(user)
    ApiKey.create!(user: user, name: "Default")
  end

  def seed_credits(user)
    CreditLedger.create!(user: user, amount: 30, description: "Welcome credits")
  end

  def send_welcome(user)
    WelcomeMailer.welcome(user).deliver_later
  end
end

# Controller is one line
result = Onboarding::Facade.call(registration_params)
```

## Why This Is Good

- **One entry point for a complex operation.** `IndexFacade.new.index_project(project, files)` hides change detection, chunking, embedding, upserting, and timestamp updates behind one call.
- **Subsystem classes remain independent.** `Chunker`, `ChangeDetector`, and `EmbeddingClient` don't know about each other. The facade coordinates them.
- **Easy to test at two levels.** Integration test: call the facade and assert the database state. Unit tests: test each subsystem class in isolation.
- **Callers are decoupled from subsystem changes.** If you replace the chunker algorithm, the facade's interface doesn't change. Callers never know.

## When To Apply

- **Multi-step operations.** Onboarding, order processing, codebase indexing — anything that coordinates 3+ subsystems.
- **Complex API integrations.** Wrapping a third-party SDK's 5-step authentication flow behind `Auth::Facade.authenticate(credentials)`.
- **Simplifying legacy code.** Wrap a messy subsystem in a clean facade before refactoring the internals.

## When NOT To Apply

- **Single-step operations.** Wrapping `User.create!(params)` in a facade adds a pointless layer.
- **Don't hide everything.** If callers sometimes need fine-grained control over individual subsystems, expose them alongside the facade — don't force everything through one entry point.

## Rails Connection

Most Rails service objects ARE facades. `Orders::CreateService` is a facade over validation, persistence, payment charging, and notification. The pattern is so common in Rails that we don't always name it — but recognizing it helps design better services.
