# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      base.state_machine.after_transition(
        to: :confirm,
        do: :log_confirm_transition
      )
    end

    def payment_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] payment_required? called. iPay payment found: #{ipay_payment}")
      return false if ipay_payment
      super
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] confirmation_required? called. iPay payment found: #{ipay_payment}")
      return true if ipay_payment
      super
    end

    def log_confirm_transition
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Transitioned to confirm state")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Next step: #{checkout_steps[checkout_steps.index(state) + 1]}")
      Rails.logger.info("[IPAY_DEBUG][Order-#{number}] Payment state: #{payment_state}, Payments: #{payments.map { |p| "#{p.id}:#{p.state}" }.join(', ')}")
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
