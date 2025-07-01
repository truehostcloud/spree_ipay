class AddIpayPaymentMethod < ActiveRecord::Migration[6.1]
  def up
    return if Spree::PaymentMethod.exists?(type: 'Spree::PaymentMethod::Ipay')

    # ✅ Get the store
    store = Spree::Store.default || Spree::Store.first

    # 🔐 Ensure store is found before proceeding
    raise "No Spree::Store found. Please create a store before running this migration." if store.nil?

    Spree::PaymentMethod::Ipay.create!(
      name: 'iPay Mobile Money',
      description: 'Pay using M-Pesa, Airtel Money and other mobile money services',
      active: true,
      display_on: 'both',
      preferences: {
        vendor_id: 'truehost',
        hash_key: '5efhkkfv865fvbgbjhgb8g5b4lr',
        test_mode: true,
        currency: 'KES'
      },
      stores: [store]  # ✅ This is mandatory
    )
  end

  def down
    Spree::PaymentMethod.where(type: 'Spree::PaymentMethod::Ipay').destroy_all
  end
end
