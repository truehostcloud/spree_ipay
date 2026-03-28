module Spree
  class IpaySource < Spree::Base
    attribute :user_id, :integer

    belongs_to :payment_method, class_name: 'Spree::PaymentMethod::Ipay', optional: true
    belongs_to :user, class_name: Spree.user_class.to_s, optional: true
    has_many :payments, as: :source, class_name: 'Spree::Payment', dependent: :destroy

    # Validations
    validates :phone, presence: true

    def user_id=(value)
      super(value.presence)
      self.user = Spree.user_class.find_by(id: self[:user_id]) if self[:user_id].present?
    end

    # Callbacks
    before_validation :normalize_phone, if: :will_save_change_to_phone?

    private

    def normalize_phone
      return if phone.blank?

      # Remove any non-digit characters
      self.phone = phone.gsub(/\D/, '')

      # Add country code if missing (assuming Kenya +254)
      return unless phone.start_with?('0') && phone.length == 10

      self.phone = "254#{phone[1..-1]}"
    end
  end
end
