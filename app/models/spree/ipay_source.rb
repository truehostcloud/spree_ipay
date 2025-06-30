module Spree
  class IpaySource < Spree::Base
    # Associations
    belongs_to :payment_method, class_name: 'Spree::PaymentMethod::Ipay', optional: true
    has_many :payments, as: :source, class_name: 'Spree::Payment', dependent: :destroy

    # Validations
    validates :phone, presence: true
    
    # Callbacks
    before_validation :normalize_phone, if: :phone_changed?

    private

    def normalize_phone
      return if phone.blank?
      
      # Remove any non-digit characters
      self.phone = phone.gsub(/\D/, '')
      
      # Add country code if missing (assuming Kenya +254)
      if phone.start_with?('0') && phone.length == 10
        self.phone = "254#{phone[1..-1]}"
      end
    end
  end
end
