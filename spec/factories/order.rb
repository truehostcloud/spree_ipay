# frozen_string_literal: true

FactoryBot.define do
  factory :order, class: 'Spree::Order' do
    sequence(:number) { |n| "R#{1000 + n}" }
    email { 'customer@example.com' }
    total { 100.0 }
    state { 'cart' }
    store { Spree::Store.first || association(:store) }
    trait :with_totals do
      after(:create) do |order|
        order.update_columns(total: 100.0)
      end
    end
  end
  factory :order_with_totals, parent: :order do
    with_totals
  end
end
