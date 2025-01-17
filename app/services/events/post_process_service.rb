# frozen_string_literal: true

module Events
  class PostProcessService < BaseService
    def initialize(event:)
      @organization = event.organization
      @event = event
      super
    end

    def call
      event.external_customer_id ||= customer&.external_id

      unless event.external_subscription_id
        Deprecation.report('event_missing_external_subscription_id', organization.id)
      end

      # NOTE: prevent subscription if more than 1 subscription is active
      #       if multiple terminated matches the timestamp, takes the most recent
      if !event.external_subscription_id && subscriptions.count(&:active?) <= 1
        event.external_subscription_id ||= subscriptions.first&.external_id
      end

      event.save!

      expire_cached_charges(subscriptions)

      handle_pay_in_advance

      result.event = event
      result
    rescue ActiveRecord::RecordInvalid => e
      deliver_error_webhook(error: e.record.errors.messages)

      result
    rescue ActiveRecord::RecordNotUnique
      deliver_error_webhook(error: {transaction_id: ['value_already_exist']})

      result
    end

    private

    attr_reader :event

    delegate :organization, to: :event

    def customer
      return @customer if defined? @customer

      @customer = if event.external_subscription_id
        organization.subscriptions.find_by(external_id: event.external_subscription_id)&.customer
      else
        Customer.find_by(external_id: event.external_customer_id, organization_id: organization.id)
      end
    end

    def subscriptions
      return @subscriptions if defined? @subscriptions

      subscriptions = if customer && event.external_subscription_id.blank?
        customer.subscriptions
      else
        organization.subscriptions.where(external_id: event.external_subscription_id)
      end
      return unless subscriptions

      @subscriptions = subscriptions
        .where("date_trunc('second', started_at::timestamp) <= ?::timestamp", event.timestamp)
        .where(
          "terminated_at IS NULL OR date_trunc('second', terminated_at::timestamp) >= ?",
          event.timestamp
        )
        .order('terminated_at DESC NULLS FIRST, started_at DESC')
    end

    def billable_metric
      @billable_metric ||= organization.billable_metrics.find_by(code: event.code)
    end

    def expire_cached_charges(subscriptions)
      active_subscription = subscriptions.select(&:active?)
      return if active_subscription.blank?
      return unless billable_metric

      charges = billable_metric.charges
        .joins(:plan)
        .where(plans: {id: active_subscription.map(&:plan_id)})

      charges.each do |charge|
        active_subscription.each do |subscription|
          Subscriptions::ChargeCacheService.new(subscription:, charge:).expire_cache
        end
      end
    end

    def handle_pay_in_advance
      return unless billable_metric

      # NOTE: `custom_agg` and `count_agg` are the only 2 aggregations
      #       that don't require a field set in property.
      #       For other aggregation, if the field isn't set we shouldn't create a fee/invoice.
      processable_event = billable_metric.count_agg? ||
        billable_metric.custom_agg? ||
        event.properties[billable_metric.field_name].present?
      return unless processable_event

      charges.where(invoiceable: false).find_each do |charge|
        Fees::CreatePayInAdvanceJob.perform_later(charge:, event:)
      end

      charges.where(invoiceable: true).find_each do |charge|
        Invoices::CreatePayInAdvanceChargeJob.perform_later(charge:, event:, timestamp: event.timestamp)
      end
    end

    def charges
      return Charge.none unless subscriptions.first

      subscriptions
        .first
        .plan
        .charges
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metric: {code: event.code})
    end

    def deliver_error_webhook(error:)
      return unless organization.webhook_endpoints.any?

      SendWebhookJob.perform_later('event.error', event, {error:})
    end
  end
end
