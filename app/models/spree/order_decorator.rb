# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      base.state_machine.before_transition(
        to: :confirm,
        do: :log_before_confirm
      )

      base.state_machine.after_transition(
        to: :confirm,
        do: :log_after_confirm
      )

      base.state_machine.after_transition(
        to: :complete,
        do: :log_complete_transition
      )

      # ✅ Only allow completing if iPay payment is confirmed
      base.state_machine.before_transition(to: :complete) do |order|
        order.allow_complete_with_ipay_payment?
      end
    end

    # ✅ Ensures only iPay orders are guarded
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

    # ✅ Optional logging hooks
    def log_before_confirm; end
    def log_after_confirm; end
    def log_complete_transition; end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
