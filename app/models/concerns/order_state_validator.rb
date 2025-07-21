# frozen_string_literal: true

module OrderStateValidator
  extend ActiveSupport::Concern

  included do
    validate :validate_state_transition, on: :update, if: :state_changed?
  end

  private

  VALID_TRANSITIONS = {
    'cart'     => ['address'],
    'address'  => ['delivery'],
    'delivery' => ['payment', 'confirm', 'complete'],
    'payment'  => ['confirm', 'complete'],
    'confirm'  => ['complete']
  }.freeze

  def validate_state_transition
    return unless state_was.present? && state.present?
    
    allowed_states = VALID_TRANSITIONS[state_was] || []
    
    unless allowed_states.include?(state)
      errors.add(:state, "cannot transition from #{state_was} to #{state}")
      
      # If trying to go from address to complete, force to delivery
      if state_was == 'address' && state == 'complete'
        self.state = 'delivery'
        Rails.logger.warn("Invalid transition from address to complete. Redirecting to delivery.")
      end
    end
  end
end
