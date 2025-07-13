require 'rails_helper'

RSpec.feature 'iPay Checkout Flow', type: :feature, js: true do
  let!(:store) { create(:store) }
  let!(:country) { create(:country, states_required: true) }
  let!(:state) { create(:state, country: country) }
  let!(:shipping_method) { create(:shipping_method) }
  let!(:stock_location) { create(:stock_location) }
  let!(:product) { create(:product, name: 'Test Product') }
  let!(:payment_method) { create(:ipay_payment_method, environment: 'test') }

  before do
    product.master.stock_items.first.update(count_on_hand: 10)
  end

  scenario 'completes checkout with iPay' do
    # Add product to cart
    visit spree.product_path(product)
    click_button 'Add To Cart'
    
    # Proceed to checkout
    click_button 'Checkout'
    
    # Fill in address
    fill_in 'order_email', with: 'test@example.com'
    within('#billing') do
      fill_in 'First Name', with: 'John'
      fill_in 'Last Name', with: 'Doe'
      fill_in 'Street Address', with: '123 Test St'
      fill_in 'City', with: 'Test City'
      select country.name, from: 'Country'
      select state.name, from: 'State'
      fill_in 'Zip', with: '12345'
      fill_in 'Phone', with: '254712345678'
    end
    click_button 'Save and Continue'
    
    # Select shipping method
    choose shipping_method.name
    click_button 'Save and Continue'
    
    # Select payment method
    choose 'iPay'
    fill_in 'Phone Number', with: '254712345678'
    click_button 'Save and Continue'
    
    # Confirm order
    click_button 'Place Order'
    
    # Verify order completion
    expect(page).to have_content('Order processed successfully')
    expect(page).to have_content('Your order has been processed successfully')
  end
end
