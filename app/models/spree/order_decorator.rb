# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      # Block transition to :complete unless iPay payment is completed
      base.state_machine.before_transition(
        to: :complete,
        guard: ->(order) { order.ipay_payment_confirmed? }
      )
    end

    # Only allow order to complete if there's a completed iPay payment
    def ipay_payment_confirmed?
      payments.valid.any? do |p|
        p.payment_method.is_a?(Spree::PaymentMethod::Ipay) && p.completed?
      end
    end

    # Optional: block advancing to next step if iPay payment is still pending
    def next
      if state == 'confirm' && ipay_payment_pending?
        return false
      end
      super
    end

    def ipay_payment_pending?
      payments.valid.any? do |p|
        p.payment_method.is_a?(Spree::PaymentMethod::Ipay) && !p.completed?
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
