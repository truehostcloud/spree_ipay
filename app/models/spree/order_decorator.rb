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
