# frozen_string_literal: true

# Positive fixture: nested _attributes with %i[] symbol array
class InvoicesController < ApplicationController
  def create
    @invoice = Invoice.new(invoice_params)
    @invoice.save
  end

  private

  def invoice_params
    params.require(:invoice).permit(:number, customer_attributes: %i[id name credit_limit])
  end
end
