# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      base.state_machine.before_transition(to: :complete) do |order|
        order.allow_complete_with_ipay_payment?
      end
    end
    

    def payment_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      ipay_payment ? false : super
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      ipay_payment || super
    end
    
    def log_before_confirm
      # No logging needed
    end
    
    def log_after_confirm
      # No logging needed
    end
    
    def log_complete_transition
      # No logging needed
    end
    def payment_required?
      ipay_payment_completed = payments.valid.any? do |p|
        p.payment_method.is_a?(Spree::PaymentMethod::Ipay) && p.completed?
      end
      ipay_payment_completed ? false : super
    end

    # Only allow order completion if there is a completed iPay payment
    def allow_complete_with_ipay_payment?
      payments.valid.any? do |payment|
        payment.payment_method.is_a?(Spree::PaymentMethod::Ipay) && payment.completed?
      end
    end
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
