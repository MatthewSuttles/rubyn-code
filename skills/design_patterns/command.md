# Design Pattern: Command

## Pattern

Encapsulate a request as an object, allowing you to parameterize clients with different requests, queue requests, log them, and support undo operations. In Ruby/Rails, service objects are already a form of the Command pattern — each one encapsulates a single operation.

```ruby
# Commands as objects — queueable, loggable, undoable
class Commands::Base
  attr_reader :executed_at, :result

  def execute
    raise NotImplementedError
  end

  def undo
    raise NotImplementedError, "#{self.class} does not support undo"
  end

  def description
    raise NotImplementedError
  end
end

class Commands::ChangeOrderStatus < Commands::Base
  def initialize(order, new_status, actor:)
    @order = order
    @new_status = new_status
    @actor = actor
    @previous_status = order.status
  end

  def execute
    @order.update!(status: @new_status)
    @executed_at = Time.current
    AuditLog.record(actor: @actor, action: description, target: @order)
    @result = :success
  end

  def undo
    @order.update!(status: @previous_status)
    AuditLog.record(actor: @actor, action: "Undo: #{description}", target: @order)
  end

  def description
    "Changed order #{@order.reference} from #{@previous_status} to #{@new_status}"
  end
end

class Commands::ApplyDiscount < Commands::Base
  def initialize(order, discount_code, actor:)
    @order = order
    @discount_code = discount_code
    @actor = actor
    @previous_discount = order.discount_amount
  end

  def execute
    discount = Discount.active.find_by!(code: @discount_code)
    amount = discount.calculate(@order.subtotal)
    @order.update!(discount_amount: amount, discount_code: @discount_code)
    @executed_at = Time.current
    @result = :success
  end

  def undo
    @order.update!(discount_amount: @previous_discount, discount_code: nil)
  end

  def description
    "Applied discount #{@discount_code} to order #{@order.reference}"
  end
end

# Command history for undo support
class CommandHistory
  def initialize
    @history = []
  end

  def execute(command)
    command.execute
    @history.push(command)
    command
  end

  def undo_last
    command = @history.pop
    return unless command
    command.undo
    command
  end

  def log
    @history.map { |cmd| "#{cmd.executed_at}: #{cmd.description}" }
  end
end

# Usage
history = CommandHistory.new
history.execute(Commands::ChangeOrderStatus.new(order, "confirmed", actor: admin))
history.execute(Commands::ApplyDiscount.new(order, "SAVE10", actor: admin))

# Undo last action
history.undo_last  # Reverses the discount
```

## Why This Is Good

- **Operations are first-class objects.** Each command can be queued, logged, serialized, and undone. You can't do this with bare method calls.
- **Audit trail is built in.** Every command has a `description` and `executed_at`. The history is an automatic audit log.
- **Undo support.** Each command stores the state needed to reverse itself. Admin actions, bulk operations, and user-facing "undo" features are straightforward.
- **Deferred execution.** Commands can be serialized and executed later — in a background job, after approval, or in a batch.

## When To Apply

- **Admin actions that need audit trails.** Status changes, refunds, account modifications — wrap each in a command that logs who did what.
- **User-facing undo.** "Undo archive", "undo delete", "undo status change" — commands store previous state.
- **Batch operations.** Collect multiple commands, validate them all, then execute as a group.
- **Background job payloads.** Serialize a command and enqueue it. The job deserializes and executes.

## When NOT To Apply

- **Simple CRUD without undo or audit.** A standard `Order.create!(params)` doesn't need a Command wrapper.
- **Your existing service objects already work.** If service objects handle your use case without undo or queueing needs, don't add Command on top.
- **Fire-and-forget operations.** If you never need to undo or replay the action, a plain service object is simpler.
