# frozen_string_literal: true

module Spree
  module OrderDecorator
    VALID_TRANSITIONS = {
      'cart'     => ['address'],
      'address'  => ['delivery'],
      'delivery' => ['payment', 'confirm', 'complete'],
      'payment'  => ['confirm', 'complete'],
      'confirm'  => ['complete']
    }.freeze

    def self.prepended(base)
      base.state_machine.before_transition do |order, transition|
        current_state = transition.from_name.to_s
        next_state = transition.to_name.to_s
        
        # Skip validation for certain cases
        next if current_state == next_state
        next if %w[confirm complete].include?(next_state) && order.payments.any? { |p| p.payment_method.is_a?(Spree::PaymentMethod::Ipay) }
        
        allowed_states = VALID_TRANSITIONS[current_state] || []
        
        unless allowed_states.include?(next_state)
          Rails.logger.error("Invalid state transition: #{current_state} -> #{next_state}")
          
          # Force to a valid state if possible
          if current_state == 'address' && next_state == 'complete'
            order.state = 'delivery'
            next :halt
          end
          
          raise StateMachines::InvalidTransition.new(
            order,
            order.state_machine,
            :run_transitions,
            "Cannot transition from #{current_state} to #{next_state}"
          )
        end
      end
      
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
  end
end

Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
