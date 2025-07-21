# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      base.state_machine.before_transition(
        to: :complete,
        guard: ->(order) { order.allow_complete_with_ipay_payment? }
      )
    end

    def confirmation_required?
      true
    end

    # Allow completion only if there's no iPay payment or it's completed
    def allow_complete_with_ipay_payment?
      return true unless has_ipay_payment?
      ipay_payment_confirmed?
    end

    def has_ipay_payment?
      payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
    end

    def ipay_payment_confirmed?
      payments.valid.any? do |p|
        p.payment_method.is_a?(Spree::PaymentMethod::Ipay) && p.completed?
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)