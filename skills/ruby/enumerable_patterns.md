# Ruby: Enumerable Patterns

## Pattern

Choose the most expressive Enumerable method for the operation. Ruby provides specific methods for specific transformations — using the right one makes code self-documenting and often more performant.

```ruby
users = [user_a, user_b, user_c, user_d]

# TRANSFORMING: map when you want a new array of transformed elements
emails = users.map(&:email)
# => ["alice@example.com", "bob@example.com", ...]

# FILTERING: select/reject for keeping/removing elements
active_users = users.select(&:active?)
inactive_users = users.reject(&:active?)

# FINDING: find for the first match, detect is an alias
admin = users.find { |u| u.role == :admin }

# CHECKING: any?/all?/none? for boolean questions about the collection
has_admins = users.any? { |u| u.role == :admin }
all_confirmed = users.all?(&:confirmed?)
no_banned = users.none?(&:banned?)

# ACCUMULATING: each_with_object for building a new structure
users_by_role = users.each_with_object({}) do |user, hash|
  (hash[user.role] ||= []) << user
end

# COUNTING: tally for frequency counts (Ruby 2.7+)
role_counts = users.map(&:role).tally
# => { admin: 1, user: 3 }

# GROUPING: group_by for categorizing
by_plan = users.group_by(&:plan)
# => { free: [user_a, user_c], pro: [user_b, user_d] }

# FLATTENING + TRANSFORMING: flat_map when map would return nested arrays
all_orders = users.flat_map(&:orders)
# Instead of: users.map(&:orders).flatten

# SORTING: sort_by for sorting by a derived value
by_name = users.sort_by(&:name)
by_newest = users.sort_by(&:created_at).reverse

# CHUNKING: chunk for grouping consecutive elements
log_lines.chunk { |line| line.start_with?("ERROR") }.each do |is_error, lines|
  report_errors(lines) if is_error
end

# INDEXING: index_by (Rails) or to_h for key-value lookup
users_by_id = users.index_by(&:id)
# => { 1 => user_a, 2 => user_b, ... }

# ZIPPING: zip for pairing elements from two arrays
names = ["Alice", "Bob"]
scores = [95, 87]
paired = names.zip(scores)
# => [["Alice", 95], ["Bob", 87]]
```

## Why This Is Good

- **Self-documenting.** `users.select(&:active?)` reads like English. The method name tells you the intent — filtering. No comments needed.
- **No intermediate state.** Each method returns a new array (or enumerator). No temporary variables, no mutation, no `<< item` inside a loop.
- **Chainable.** Methods compose naturally: `users.select(&:active?).sort_by(&:name).map(&:email)` is a pipeline where each step is clear.
- **Performance.** Specific methods like `any?` short-circuit (stop iterating once the answer is known). `flat_map` avoids creating an intermediate nested array. `tally` is a single pass instead of `group_by` + `transform_values(&:count)`.
- **Symbol-to-proc shorthand.** `&:method_name` is idiomatic Ruby. Use it whenever the block is a single method call on the yielded element.

## Anti-Pattern

Using `each` with manual accumulation for everything:

```ruby
# Collecting results manually
emails = []
users.each do |user|
  emails << user.email
end

# Filtering manually
active_users = []
users.each do |user|
  if user.active?
    active_users << user
  end
end

# Building a hash manually
users_by_role = {}
users.each do |user|
  if users_by_role[user.role]
    users_by_role[user.role] << user
  else
    users_by_role[user.role] = [user]
  end
end

# Counting manually
admin_count = 0
users.each do |user|
  admin_count += 1 if user.role == :admin
end
```

## Why This Is Bad

- **Verbose.** 4 lines for what `map` does in 1. Multiply this across a codebase and you have thousands of unnecessary lines.
- **Mutable state.** `emails = []` followed by `emails << ...` is imperative mutation. It's easy to accidentally push into the wrong array, skip the push, or modify the array elsewhere.
- **Hides intent.** Reading `emails = []` followed by a loop, you have to trace through the loop body to understand "oh, this is collecting emails." With `map(&:email)`, the intent is immediate.
- **Error-prone.** The manual hash building has a nil check that `group_by` handles automatically. The manual count is off-by-one prone. These bugs don't exist when you use the right method.
- **Not chainable.** The result is a variable, not a method return. You can't compose it with another operation without assigning to yet another variable.

## When To Apply

- **Always.** There is no case where manual `each` + accumulation is better than the appropriate Enumerable method. This is idiomatic Ruby — it's expected.
- **In ActiveRecord contexts** — prefer database operations (`pluck`, `where`, `group`, `count`) over loading records and using Ruby enumerables. But when you have the collection in memory already, use enumerables.

## When NOT To Apply

- **Don't chain excessively.** `users.select(&:active?).reject(&:banned?).sort_by(&:name).first(10).map(&:email)` is readable. Adding 3 more transformations is not. Break into named intermediate variables or methods if the chain exceeds 4-5 steps.
- **Don't use enumerables on large database sets.** `User.all.select(&:active?)` loads every user into memory then filters in Ruby. Use `User.where(active: true)` to filter in the database.
- **`each` is correct for side effects.** When the purpose is to DO something (send emails, update records, log output) rather than COMPUTE something, `each` is the right choice. Don't force `map` when you don't need the return value.

## Edge Cases

**`reduce` vs `each_with_object`:**
Use `each_with_object` for building hashes and arrays. Use `reduce` for computing a single value (sum, product). The difference: `reduce` requires you to return the accumulator from every block; `each_with_object` doesn't.

```ruby
# each_with_object: cleaner for hash building
users.each_with_object({}) { |u, h| h[u.id] = u.name }

# reduce: cleaner for arithmetic
order.line_items.reduce(0) { |sum, item| sum + item.total }

# But for sums, just use .sum
order.line_items.sum(&:total)
```

**`map` + `compact` vs `filter_map`:**
Use `filter_map` (Ruby 2.7+) when the transformation might return nil and you want to skip nils:

```ruby
# Instead of
users.map { |u| u.profile&.avatar_url }.compact

# Use
users.filter_map { |u| u.profile&.avatar_url }
```

**Lazy enumerables for large/infinite collections:**

```ruby
# Process a huge file without loading it all into memory
File.open("huge.csv").lazy.map { |line| parse(line) }.select(&:valid?).first(100)
```

**`each_slice` and `each_cons` for batching:**

```ruby
# Process in batches of 100
users.each_slice(100) { |batch| BulkEmailJob.perform_later(batch.map(&:id)) }

# Sliding window of 3
temperatures.each_cons(3) { |window| detect_trend(window) }
```
