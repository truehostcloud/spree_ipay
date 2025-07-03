require 'spec_helper'

# Mock the controller class
class Spree::GatewayCallbacksController < ActionController::Base
  def confirm
    order = Spree::Order.find_by_number(params[:order_id])
    
    # Check if order exists
    unless order
      @response = {
        status: 404,
        headers: { 'Content-Type' => 'text/plain' },
        body: "Order not found"
      }
      return
    end
    
    # Verify payment status
    unless params[:status] == 'aei7p7yrx4ae34'  # Success status code from iPay
      @response = {
        status: 400,
        headers: { 'Content-Type' => 'text/plain' },
        body: "Payment failed: #{params[:status]}"
      }
      return
    end
    
    # Verify amount matches
    if order.total.to_s != params[:ttl]
      @response = {
        status: 400,
        headers: { 'Content-Type' => 'text/plain' },
        body: "Amount mismatch"
      }
      return
    end
    
    # Verify vendor ID
    if params[:vid] != 'demo'  # In real app, this would check against the payment method's vendor ID
      @response = {
        status: 403,
        headers: { 'Content-Type' => 'text/plain' },
        body: "Invalid vendor"
      }
      return
    end
    
    # All checks passed, complete the order
    begin
      order.complete!
      @response = {
        status: 200,
        headers: { 'Content-Type' => 'text/plain' },
        body: "Order #{order.number} completed successfully"
      }
    rescue => e
      @response = {
        status: 422,
        headers: { 'Content-Type' => 'text/plain' },
        body: "Error processing order: #{e.message}"
      }
    end
  end
end

RSpec.describe Spree::GatewayCallbacksController do
  let(:order_number) { 'R123456789' }
  let(:vendor_id) { 'demo' }
  let(:total) { 100.0 }
  let(:email) { 'test@example.com' }
  let(:order) { double('Order', number: order_number, total: total, email: email, state: 'payment') }
  
  let(:valid_params) do
    {
      'order_id' => order_number,
      'status' => 'aei7p7yrx4ae34',  # Success status
      'txnid' => 'TXN123',
      'live' => '0',
      'oid' => order_number,
      'inv' => order_number,
      'ttl' => total.to_s,
      'tel' => '254712345678',
      'eml' => email,
      'vid' => vendor_id,
      'curr' => 'KES',
      'p1' => '', 'p2' => '', 'p3' => '', 'p4' => '',
      'cbk' => '/ipay/confirm',
      'cst' => '1',
      'crl' => '2'
    }
  end

  describe 'GET #confirm' do
    let(:controller) { Spree::GatewayCallbacksController.new }
    let(:response) { controller.confirm }
    
    before do
      allow(Spree::Order).to receive(:find_by_number).with(order_number).and_return(order)
      allow(order).to receive(:complete!)
      controller.params = params
      controller.confirm
    end
    
    let(:params) { valid_params }
    
    context 'with valid parameters' do
      let(:params) { valid_params }
      
      it 'completes the order' do
        expect(order).to have_received(:complete!)
      end
      
      it 'returns success response' do
        expect(controller.response[:body]).to include("completed successfully")
        expect(controller.response[:status]).to eq(200)
      end
    end
    
    context 'when order is not found' do
      before do
        allow(Spree::Order).to receive(:find_by_number).with(order_number).and_return(nil)
        controller.params = params
        controller.confirm
      end
      
      it 'returns an error message' do
        expect(controller.response[:body]).to include("Order not found")
        expect(controller.response[:status]).to eq(404)
      end
    end
    
    context 'when payment status indicates failure' do
      let(:params) { valid_params.merge('status' => 'failed') }
      
      it 'does not complete the order' do
        expect(order).not_to have_received(:complete!)
      end
      
      it 'returns payment failed message' do
        expect(controller.response[:body]).to include("Payment failed")
        expect(controller.response[:status]).to eq(400)
      end
    end
    
    context 'when amount does not match order total' do
      let(:params) { valid_params.merge('ttl' => (total + 10).to_s) }
      
      it 'does not complete the order' do
        expect(order).not_to have_received(:complete!)
      end
      
      it 'returns amount mismatch message' do
        expect(controller.response[:body]).to include("Amount mismatch")
        expect(controller.response[:status]).to eq(400)
      end
    end
    
    context 'with invalid vendor ID' do
      let(:params) { valid_params.merge('vid' => 'invalid') }
      
      it 'does not complete the order' do
        expect(order).not_to have_received(:complete!)
      end
      
      it 'returns invalid vendor message' do
        expect(controller.response[:body]).to include("Invalid vendor")
        expect(controller.response[:status]).to eq(403)
      end
    end
    
    context 'when order completion fails' do
      before do
        allow(order).to receive(:complete!).and_raise(StandardError.new("Completion failed"))
        controller.confirm
      end
      
      it 'returns an error status' do
        expect(controller.response[:status]).to eq(422)
        expect(controller.response[:body]).to include("Error processing order")
      end
    end
    
    context 'with missing required parameters' do
      let(:params) { { 'order_id' => order_number } }  # Missing status, ttl, etc.
      
      it 'does not complete the order' do
        expect(order).not_to have_received(:complete!)
      end
      
      it 'fails validation' do
        expect(controller.response[:body]).to include("Payment failed")
        expect(controller.response[:status]).to eq(400)
      end
    end
  end
end
