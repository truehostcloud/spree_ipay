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
        order.allow_complete_with_ipay_payment?
      end
    end

    # Override to skip payment requirement for iPay payments
    def payment_required?
      return false if ipay_payment_pending_or_completed?
      super
    end

    # Require confirmation for iPay payments
    def confirmation_required?
      return true if has_ipay_payment?
      super
    end
    
    # Disable logging methods to reduce noise
    def log_before_confirm; end
    def log_after_confirm; end
    def log_complete_transition; end

    # Check if order has any iPay payment method
    def has_ipay_payment?
      payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
    end

    # Check if order has a completed iPay payment
    def has_completed_ipay_payment?
      payments.valid.any? do |p|
        p.payment_method.is_a?(Spree::PaymentMethod::Ipay) && p.completed?
      end
    end

    # Check for either pending or completed iPay payments
    def ipay_payment_pending_or_completed?
      payments.valid.any? do |p|
        p.payment_method.is_a?(Spree::PaymentMethod::Ipay) && (p.pending? || p.completed?)
      end
    end

    # Only allow order completion if there is a completed iPay payment
    def allow_complete_with_ipay_payment?
      return true unless has_ipay_payment?
      has_completed_ipay_payment?
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
