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
      base.state_machine.before_transition(to: :complete) do |order|
        order.ipay_payment_confirmed?
      end
    end

    def ipay_payment_confirmed?
      payments.valid.any? do |p|
        p.payment_method.is_a?(Spree::PaymentMethod::Ipay) && p.completed?
      end
    end

    def log_before_confirm; end
    def log_after_confirm; end
    def log_complete_transition; end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
