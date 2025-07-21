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
    end

    def payment_required?
      return false if paid?
      return super unless has_ipay_payments?
      return false if Spree::Payment.has_pending_ipay_payment?(self)
      
      ipay_payment = payments.valid.iPay.last
      ipay_payment.nil? || ipay_payment.completed? || ipay_payment.source&.status == 'completed'
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      ipay_payment || super
    end
    
    private
    
    def has_ipay_payments?
      payments.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
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
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
