# frozen_string_literal: true

module Events
  class PayInAdvanceService < BaseService
    def initialize(event:)
      @event = Events::CommonFactory.new_instance(source: event)
      super
    end

    def call
      return unless billable_metric

      charges.where(invoiceable: false).find_each do |charge|
        Fees::CreatePayInAdvanceJob.perform_later(charge:, event: event.as_json)
      end

      return unless can_process_event_for_invoice?

      charges.where(invoiceable: true).find_each do |charge|
        Invoices::CreatePayInAdvanceChargeJob.perform_later(charge:, event: event.as_json, timestamp: event.timestamp)
      end

      result.event = event
      result
    end

    private

    attr_reader :event

    delegate :billable_metric, :properties, :charges, to: :event

    def charges
      return Charge.none unless event.subscription

      event.subscription
        .plan
        .charges
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metrics: {id: event.billable_metric.id})
    end

    def can_process_event_for_invoice?
      billable_metric.count_agg? || billable_metric.custom_agg? || properties[billable_metric.field_name].present?
    end
  end
end
