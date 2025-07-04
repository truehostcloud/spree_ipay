# frozen_string_literal: true

FactoryBot.define do
  factory :store, class: 'Spree::Store' do
    name { 'Test Store' }
    url { 'test.local' }
    code { 'test' }
    default_currency { 'USD' }
    mail_from_address { 'test@example.com' }
  end
end
