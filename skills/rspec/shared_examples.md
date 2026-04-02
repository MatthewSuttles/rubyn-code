# RSpec: Shared Examples

## Pattern

Use `shared_examples` to DRY up specs that verify the same behavior across multiple contexts. Use `shared_context` for shared setup. Keep shared examples focused on one behavior. Pass parameters via `let`, block, or arguments.

```ruby
# spec/support/shared_examples/authenticated_endpoint.rb
RSpec.shared_examples "an authenticated endpoint" do
  context "without API key" do
    it "returns 401" do
      make_request(api_key: nil)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with revoked API key" do
    let(:api_key) { create(:api_key, :revoked) }

    it "returns 401" do
      make_request(api_key: api_key.raw_key)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with expired API key" do
    let(:api_key) { create(:api_key, :expired) }

    it "returns 401" do
      make_request(api_key: api_key.raw_key)
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

```ruby
# spec/support/shared_examples/credit_deducting_endpoint.rb
RSpec.shared_examples "a credit-deducting endpoint" do
  it "deducts credits on success" do
    expect { make_request }.to change { user.credit_ledger_entries.count }.by(1)
  end

  it "records the interaction" do
    expect { make_request }.to change(Interaction, :count).by(1)
  end

  context "with insufficient credits" do
    before do
      allow_any_instance_of(Credits::BalanceChecker).to receive(:sufficient?).and_return(false)
    end

    it "returns 402" do
      make_request
      expect(response).to have_http_status(:payment_required)
    end

    it "does not call Claude" do
      make_request
      expect(Ai::ClaudeClient).not_to have_received(:call)
    end
  end
end
```

```ruby
# spec/support/shared_examples/project_scoped_endpoint.rb
RSpec.shared_examples "a project-scoped endpoint" do
  context "when user is not a member of the project" do
    let(:other_project) { create(:project) }

    it "returns 403" do
      make_request(project_id: other_project.id)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "when project does not exist" do
    it "returns 404" do
      make_request(project_id: 999999)
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

Using shared examples in specs:

```ruby
# spec/requests/api/v1/ai/refactor_spec.rb
RSpec.describe "POST /api/v1/ai/refactor", type: :request do
  let(:user) { create(:user, :pro) }
  let(:project) { create(:project) }
  let(:membership) { create(:project_membership, user: user, project: project) }

  def make_request(api_key: user.api_keys.first.raw_key, project_id: project.id)
    post "/api/v1/ai/refactor",
         params: { file_path: "app/controllers/orders_controller.rb", file_content: "...", project_id: project_id },
         headers: { "Authorization" => "Bearer #{api_key}" }
  end

  before { membership }

  it_behaves_like "an authenticated endpoint"
  it_behaves_like "a credit-deducting endpoint"
  it_behaves_like "a project-scoped endpoint"

  # Endpoint-specific tests
  it "returns a streaming response" do
    make_request
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include("text/event-stream")
  end
end
```

Shared context for common setup:

```ruby
# spec/support/shared_contexts/with_stubbed_claude.rb
RSpec.shared_context "with stubbed Claude" do
  let(:claude_response) { "Here is the refactored code..." }

  before do
    allow(Ai::ClaudeClient).to receive(:call).and_return(
      OpenStruct.new(
        content: claude_response,
        input_tokens: 500,
        output_tokens: 200,
        cache_read_tokens: 400,
        cache_write_tokens: 0
      )
    )
  end
end

# Usage
RSpec.describe Orders::CreateService do
  include_context "with stubbed Claude"

  it "uses the stubbed response" do
    # Claude is already stubbed
  end
end
```

## Why This Is Good

- **DRY without obscuring.** Auth checks are the same for every endpoint. Writing them once in a shared example and including them with `it_behaves_like` is clearer than copy-pasting the same 20 lines into 30 spec files.
- **Consistent coverage.** When you add a new auth check (e.g., "suspended account returns 403"), you add it to the shared example once. Every endpoint that includes it gets the new test automatically.
- **Contract enforcement.** `it_behaves_like "a credit-deducting endpoint"` acts as a contract: every AI endpoint must deduct credits. If a new endpoint doesn't pass the shared example, it's missing credit deduction logic.
- **Readable spec files.** The endpoint spec reads like a checklist: it's authenticated, it deducts credits, it's project-scoped, and here are the endpoint-specific behaviors.
- **Shared contexts reduce boilerplate.** Stubbing Claude the same way in 20 spec files is noisy. A shared context does it once and every spec file includes it by name.

## Anti-Pattern

Shared examples that are too broad, too abstract, or tightly coupled to implementation:

```ruby
# BAD: Shared example that does everything
RSpec.shared_examples "a standard API endpoint" do |method, path|
  it "requires auth" do
    send(method, path)
    expect(response).to have_http_status(:unauthorized)
  end

  it "requires project membership" do
    send(method, path, headers: auth_headers)
    expect(response).to have_http_status(:forbidden)
  end

  it "deducts credits" do
    expect { send(method, path, params: valid_params, headers: auth_headers) }
      .to change(CreditLedger, :count)
  end

  it "records the interaction" do
    expect { send(method, path, params: valid_params, headers: auth_headers) }
      .to change(Interaction, :count)
  end

  it "returns success" do
    send(method, path, params: valid_params, headers: auth_headers)
    expect(response).to have_http_status(:ok)
  end
end

# Usage becomes cryptic
it_behaves_like "a standard API endpoint", :post, "/api/v1/ai/refactor"
```

```ruby
# BAD: Shared example in a deeply nested file nobody can find
# spec/support/shared_examples/concerns/models/trackable_behavior_for_auditable_records.rb
RSpec.shared_examples "trackable auditable behavior" do
  # 50 lines of tests that are impossible to discover
end
```

## Why This Is Bad

- **God shared examples test too many things at once.** When `"a standard API endpoint"` fails, you don't know if it's an auth issue, a credit issue, or a response format issue. Smaller shared examples give focused feedback.
- **Parameterized shared examples are hard to read.** `it_behaves_like "a standard API endpoint", :post, "/api/v1/ai/refactor"` hides what's being tested. The reader has to open the shared example file to understand what 5 tests are running.
- **Over-abstracted names.** `"trackable auditable behavior"` doesn't communicate what it tests. `"an authenticated endpoint"` does. Name shared examples by the behavior they verify.
- **Hidden in deep directories.** If shared examples are buried in `spec/support/shared_examples/concerns/models/`, nobody will find or use them. Keep them in `spec/support/shared_examples/` at one level deep.

## When To Apply

- **Identical behavior across multiple specs.** Authentication, authorization, credit deduction, pagination, error handling — if 10+ specs verify the same behavior, extract it.
- **Contract testing.** "Every AI endpoint must deduct credits" is a contract. A shared example enforces it.
- **Setup that's the same across a describe group.** `shared_context` for stubbing external services, setting up test data, or configuring the test environment.

## When NOT To Apply

- **Behavior specific to one endpoint.** If only the refactor endpoint has a specific behavior, test it inline. Don't create a shared example for one consumer.
- **When the shared example needs more than 2 parameters.** If you're passing 4 arguments to configure the shared example, it's too abstract. Write the tests inline.
- **When the setup is simple.** A 2-line `before` block doesn't need a shared context. Just write the 2 lines.

## Edge Cases

**Shared examples that need different setup per includer:**
Use `let` overrides. The shared example references `let(:user)` — each including spec defines its own `user`:

```ruby
RSpec.shared_examples "a credit-deducting endpoint" do
  it "deducts from the user's balance" do
    expect { make_request }.to change { user.reload.credit_balance }
  end
end

# Spec A
let(:user) { create(:user, :pro) }
it_behaves_like "a credit-deducting endpoint"

# Spec B — different user setup, same shared example
let(:user) { create(:user, :free) }
it_behaves_like "a credit-deducting endpoint"
```

**`it_behaves_like` vs `include_examples`:**
`it_behaves_like` creates a nested context (its own describe block). `include_examples` runs the examples in the current context. Use `it_behaves_like` when you want isolation. Use `include_examples` when the examples need access to the current context's `let` variables.

**Shared examples across spec types:**
An authenticated endpoint shared example works for both request specs and API specs. Keep them generic enough to work across contexts, using `make_request` as the interface contract.
