# Create iPay payment method
unless Spree::PaymentMethod.exists?(type: 'Spree::PaymentMethod::Ipay')
  store = Spree::Store.default || Spree::Store.first
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
    stores: [store]
  )
  puts 'iPay payment method created successfully!'
else
  puts 'iPay payment method already exists'
end
