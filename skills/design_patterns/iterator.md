# Design Pattern: Iterator

## Pattern

Provide a way to traverse elements of a collection without exposing its underlying structure. Ruby's `Enumerable` module IS the Iterator pattern — include it in any class that defines `each`, and you get 50+ traversal methods for free.

```ruby
# Custom collection with Enumerable — the Ruby way to implement Iterator
class CodeChunkCollection
  include Enumerable

  def initialize
    @chunks = []
  end

  def add(chunk)
    @chunks << chunk
    self
  end

  # Define `each` — Enumerable gives you everything else
  def each(&block)
    @chunks.each(&block)
  end

  # Optional: define <=> on elements for sort methods
  def by_relevance(query_embedding)
    sort_by { |chunk| -chunk.similarity_to(query_embedding) }
  end
end

class CodeChunk
  attr_reader :file_path, :content, :embedding, :chunk_type

  def initialize(file_path:, content:, embedding:, chunk_type:)
    @file_path = file_path
    @content = content
    @embedding = embedding
    @chunk_type = chunk_type
  end

  def similarity_to(other_embedding)
    dot_product(embedding, other_embedding)
  end

  private

  def dot_product(a, b)
    a.zip(b).sum { |x, y| x * y }
  end
end

# Usage — all Enumerable methods work automatically
chunks = CodeChunkCollection.new
chunks.add(CodeChunk.new(file_path: "app/models/order.rb", content: "class Order...", embedding: [...], chunk_type: "class"))
chunks.add(CodeChunk.new(file_path: "app/services/create.rb", content: "class Create...", embedding: [...], chunk_type: "class"))

# All these work because we included Enumerable and defined each:
chunks.map(&:file_path)                    # ["app/models/order.rb", "app/services/create.rb"]
chunks.select { |c| c.chunk_type == "class" }
chunks.count                                # 2
chunks.any? { |c| c.file_path.include?("models") }
chunks.flat_map { |c| c.content.lines }
chunks.group_by(&:chunk_type)
chunks.min_by { |c| c.file_path.length }
```

### External Iterator with Enumerator

```ruby
# When you need lazy or external iteration control
class PaginatedApiIterator
  include Enumerable

  def initialize(client, endpoint, per_page: 100)
    @client = client
    @endpoint = endpoint
    @per_page = per_page
  end

  def each
    page = 1
    loop do
      results = @client.get(@endpoint, page: page, per_page: @per_page)
      break if results.empty?

      results.each { |item| yield item }
      page += 1
    end
  end
end

# Iterate over ALL pages transparently
iterator = PaginatedApiIterator.new(api_client, "/orders")
iterator.each { |order| process(order) }

# Or use lazily — only fetches pages as needed
iterator.lazy.select { |o| o["status"] == "pending" }.first(10)
```

## Why This Is Good

- **Include `Enumerable`, get 50+ methods.** `map`, `select`, `reduce`, `any?`, `none?`, `group_by`, `sort_by`, `flat_map`, `tally`, `min_by`, `max_by`, `chunk`, `each_slice` — all from defining one `each` method.
- **Lazy evaluation for large/infinite collections.** `.lazy` chains don't materialize intermediate arrays. Process a 10GB file line by line without loading it into memory.
- **Uniform interface.** Any Enumerable collection works with any method that accepts an Enumerable. Your custom collection is instantly compatible with the entire Ruby ecosystem.

## When To Apply

- **Any class that holds a collection.** If your class wraps an array, hash, or tree of objects, include `Enumerable` and define `each`.
- **Paginated API responses.** Wrap pagination logic in an iterator so callers see a seamless stream of items.
- **Tree traversal.** Define `each` to walk the tree (depth-first, breadth-first), and all Enumerable methods work on tree nodes.

## When NOT To Apply

- **You're just wrapping an Array.** If your class is a thin wrapper around `@items`, consider exposing the array directly or using `delegate :each, :map, :select, to: :items` instead of a full Enumerable include.
- **ActiveRecord already provides this.** `Order.where(status: :pending).each` — ActiveRecord relations are already iterable. Don't wrap them in another iterator.
