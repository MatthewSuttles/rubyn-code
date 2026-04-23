# frozen_string_literal: true

# Positive fixture: update_all with raw SQL string
class OrderService
  def archive_old_orders
    Order.where(status: "completed").update_all("archived = true, archived_at = NOW()")
  end
end
