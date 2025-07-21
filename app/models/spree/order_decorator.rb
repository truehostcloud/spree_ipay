# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      # Prevent order from completing unless iPay payment is confirmed
      base.state_machine.before_transition(
        to: :complete,
        guard: ->(order) { order.allow_complete_with_ipay_payment? }
      )
    end

    # Allow completion only if there's no iPay payment or it's completed
    def allow_complete_with_ipay_payment?
      return true unless has_ipay_payment?  # Let non-iPay orders proceed
      ipay_payment_confirmed?
    end

    # Check if the order has any iPay payment
    def has_ipay_payment?
      payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
    end

    # Check if the iPay payment is marked completed
    def ipay_payment_confirmed?
      payments.valid.any? do |p|
        p.payment_method.is_a?(Spree::PaymentMethod::Ipay) && p.completed?
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
