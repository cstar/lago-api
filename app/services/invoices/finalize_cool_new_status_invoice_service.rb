# frozen_string_literal: true

class FinalizeCoolNewStatusInvoiceService
  def initialize(customer:, closing_at:)
    @customer = customer
    @closing_at = closing_at
  end

  def call
    ActiveRecord::Base.transaction do
      invoice = Invoice.where(status: :cool_new_status, customer:)
        # .where("something to do with boundaries maybe")
        .first

      # What happens here?
      # extract fees not paid yet into new invoice?
      # mark this one paid, or the oether way around?
      # Should we extract the fees every time we receive an update on fee payment status?

      # in API and webhooks, the invoice ID should be invisible
      # Maybe it's best to have a new model to accumulate fees and then create the invoice ?!
    end
  end

  private

  attr_reader :customer, :closing_at
end
