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
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      return false if ipay_payment && payments.valid.iPay.any? { |p| p.completed? || p.source&.status == 'completed' }
      ipay_payment ? false : super
    end

    def confirmation_required?
      ipay_payment = payments.valid.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
      ipay_payment || super
    end
    
    # Override the next! method to prevent auto-completion for iPay orders
    def next(*args)
      return false unless payment_required?
      
      if payment? && payments.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
        # For iPay, ensure payment is completed first
        ipay_payment = payments.find_by(payment_method: Spree::PaymentMethod::Ipay.first)
        return false if ipay_payment && !ipay_payment.completed? && ipay_payment.source&.status != 'completed'
      end
      
      super
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
