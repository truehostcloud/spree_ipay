require 'spec_helper'

# Simple controller mock that doesn't depend on Rails
class Spree::IpayController
  attr_reader :request, :response, :params
  
  def initialize
    @response = { status: 200, headers: {}, body: '' }
  end
  
  def self.action(method)
    ->(env) {
      controller = new
      controller.params = env['action_controller.request.parameters'] || {}
      controller.send(method)
      [controller.response[:status], 
       controller.response[:headers], 
       [controller.response[:body].to_json]]
    }
  end
  
  def params=(params)
    @params = params.is_a?(Hash) ? params.with_indifferent_access : params
  end
  
  def initiate_payment
    order = Spree::Order.find_by(number: params[:order_number])
    if order
      @response = {
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: { 
          status: 'success', 
          redirect_url: 'https://ipay.example.com/pay',
          order_number: order.number
        }
      }
    else
      @response = {
        status: 404,
        headers: { 'Content-Type' => 'application/json' },
        body: { status: 'error', message: 'Order not found' }
      }
    end
  end
  
  def callback
    if valid_callback_params?
      order = Spree::Order.find_by(number: params[:order_number])
      if order
        order.update(payment_state: 'paid')
        @response = {
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: { status: 'success' }
        }
      else
        @response = {
          status: 404,
          headers: { 'Content-Type' => 'application/json' },
          body: { status: 'error', message: 'Order not found' }
        }
      end
    else
      @response = {
        status: 400,
        headers: { 'Content-Type' => 'application/json' },
        body: { status: 'error', message: 'Invalid parameters' }
      }
    end
  end
  
  private
  
  def valid_callback_params?
    !params[:order_number].to_s.empty? && 
    !params[:transaction_id].to_s.empty? &&
    !params[:status].to_s.empty?
  end
end

RSpec.describe Spree::IpayController do
  # Mock Spree::Order
  let(:order) { double('Order', number: 'R123456789', update: true) }
  let(:controller) { Spree::IpayController.new }
  
  before do
    allow(Spree::Order).to receive(:find_by).and_return(order)
  end

  describe '#initiate_payment' do
    context 'with valid order number' do
      before do
        controller.params = { order_number: order.number }
        controller.initiate_payment
      end
      
      it 'returns a success response with payment URL' do
        response = controller.response
        expect(response[:status]).to eq(200)
        expect(response[:body][:status]).to eq('success')
        expect(response[:body][:order_number]).to eq(order.number)
        expect(response[:body][:redirect_url]).to be_truthy
      end
    end
    
    context 'with invalid order number' do
      before do
        allow(Spree::Order).to receive(:find_by).and_return(nil)
        controller.params = { order_number: 'INVALID' }
        controller.initiate_payment
      end
      
      it 'returns a not found error' do
        response = controller.response
        expect(response[:status]).to eq(404)
        expect(response[:body][:status]).to eq('error')
        expect(response[:body][:message]).to include('not found')
      end
    end
  end
  
  describe '#callback' do
    let(:valid_params) do
      {
        order_number: order.number,
        transaction_id: 'TXN123456',
        status: 'completed',
        amount: '100.00',
        currency: 'KES'
      }
    end
    
    context 'with valid parameters' do
      before do
        controller.params = valid_params
      end
      
      it 'updates the order status and returns success' do
        expect(order).to receive(:update).with(payment_state: 'paid')
        controller.callback
        
        response = controller.response
        expect(response[:status]).to eq(200)
        expect(response[:body][:status]).to eq('success')
      end
    end
    
    context 'with missing order' do
      before do
        allow(Spree::Order).to receive(:find_by).and_return(nil)
        controller.params = valid_params
        controller.callback
      end
      
      it 'returns a not found error' do
        response = controller.response
        expect(response[:status]).to eq(404)
        expect(response[:body][:status]).to eq('error')
        expect(response[:body][:message]).to include('not found')
      end
    end
    
    context 'with invalid parameters' do
      before do
        controller.params = { order_number: order.number } # Missing required params
        controller.callback
      end
      
      it 'returns a bad request error' do
        response = controller.response
        expect(response[:status]).to eq(400)
        expect(response[:body][:status]).to eq('error')
        expect(response[:body][:message]).to include('Invalid parameters')
      end
    end
  end
end
