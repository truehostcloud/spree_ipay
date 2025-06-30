Rails.application.config.to_prepare do
  Spree::Order.class_eval do
    checkout_flow do
      go_to_state :address
      go_to_state :delivery
      go_to_state :payment
      go_to_state :confirm
      go_to_state :complete
    end
  end
end
