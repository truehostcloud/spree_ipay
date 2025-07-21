# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      # Prevent order from completing unless iPay payment is confirmed
      base.state_machine.before_transition(
        to: :complete,
        guard: ->(order) { order.ipay_payment_confirmed? }
      )
    end

    # Returns true only if a valid iPay payment is completed
    def ipay_payment_confirmed?
      payments.valid.any? do |payment|
        payment.payment_method.is_a?(Spree::PaymentMethod::Ipay) && payment.completed?
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
