# frozen_string_literal: true

module Invoices
  class CreateEndOfPeriodChargeService < BaseService
    def initialize(charge:, event:, timestamp:, invoice: nil)
      @charge = charge
      @event = event
      @timestamp = timestamp

      # NOTE: In case of retry when the creation process failed,
      #       and if the generating invoice was persisted,
      #       the process can be retried without creating a new invoice
      @invoice = invoice

      super
    end

    def call
      fees = generate_fees
      return result if fees.none?

      unless invoice
        gimme_existing_invoice_magically || create_generating_invoice
      end
      result.invoice = invoice

      ActiveRecord::Base.transaction do
        fees.each { |f| f.update!(invoice:) }

        # ... ?

        invoice.save!
      end

      # invoice.fees.each { |f| SendWebhookJob.perform_later('fee.created', f) }

      result
    rescue ActiveRecord::RecordInvalid => e
      pp e
      result.record_validation_failure!(record: e.record)
    rescue Sequenced::SequenceError
      raise
    rescue => e
      pp e
      result.fail_with_error!(e)
    end

    private

    attr_accessor :timestamp, :charge, :event, :invoice

    delegate :subscription, :customer, to: :event

    def generate_fees
      fee_result = Fees::CreatePayInAdvanceService.call(charge:, event:, estimate: true)
      fee_result.raise_if_error!
      fee_result.fees
    end

    def gimme_existing_invoice_magically
      # TODO: Add where condition to ensure the event.timestamp is within the accumulating invoice bourdaries
      # QUESTION: What if the event is received after the invoice was closed (late event) ?
      # Boundaries are not per invoice they are per subscription :D (InvoiceSubscription model)
      existing_invoice = Invoice.where(
        customer:,
        invoice_type: :end_of_period_charge,
        status: :cool_new_status # means it's still open, accumulating fees
      ).first

      return unless existing_invoice

      unless existing_invoice.subscriptions.where(id: subscription.id).exists?
        Invoices::CreateInvoiceSubscriptionService
          .call(invoice: existing_invoice, subscriptions: [subscription], timestamp:, invoicing_reason: :in_advance_charge)
          .raise_if_error!
      end

      @invoice = existing_invoice.reload
    end

    def create_generating_invoice
      invoice_result = Invoices::CreateGeneratingService.call(
        customer:,
        invoice_type: :end_of_period_charge,
        currency: customer.currency,
        datetime: Time.zone.at(timestamp) # TODO: Start of the period?
      ) do |invoice|
        Invoices::CreateInvoiceSubscriptionService
          .call(invoice:, subscriptions: [subscription], timestamp:, invoicing_reason: :in_advance_charge)
          .raise_if_error!


        invoice.payment_status = :pending
        # TODO: Ensure only one `cool_new_status` per customer at a time
        invoice.status = :cool_new_status
        invoice.save!
      end
      invoice_result.raise_if_error!

      @invoice = invoice_result.invoice
    end
  end
end
