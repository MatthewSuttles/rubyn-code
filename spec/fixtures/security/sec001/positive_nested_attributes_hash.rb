# frozen_string_literal: true

# Positive fixture: nested _attributes with empty hash (permits all nested fields)
class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)
    @order.save
  end

  private

  def order_params
    params.require(:order).permit(:total, line_item_attributes: {})
  end
end
