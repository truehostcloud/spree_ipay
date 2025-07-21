# frozen_string_literal: true

module Spree
  module OrderDecorator
    def self.prepended(base)
      base.state_machine.before_transition(
        from: :address,
        to: :complete,
        do: :prevent_invalid_transition
      )
    end

    private

    def prevent_invalid_transition
      Rails.logger.warn("Attempted invalid transition from address to complete. Forcing to delivery.")
      self.state = 'delivery'
      false # Prevent the transition
    end
  end
end

# Apply the decorator
Spree::Order.prepend(Spree::OrderDecorator) if defined?(Spree::Order)
