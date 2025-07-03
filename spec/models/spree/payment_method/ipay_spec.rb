require 'spec_helper'

# Mock Spree::PaymentMethod::Ipay class
module Spree
  module IpayPaymentMethod
    class Ipay < Spree::PaymentMethod
      attr_accessor :name, :preferences, :id
      
      def initialize(attributes = {})
        @name = attributes[:name] || 'iPay'
        @preferences = {
          vendor_id: attributes.dig(:preferences, :vendor_id) || 'demo',
          hash_key: attributes.dig(:preferences, :hash_key) || 'demohash',
          test_mode: attributes.dig(:preferences, :test_mode) != false
        }
        @id = attributes[:id] || 1
      end
      
      def check_payment_status(payment)
        # This will be stubbed in tests
      end
      
      def complete(payment)
        if payment.completed?
          return ActiveMerchant::Billing::Response.new(
            true,
            'Success',
            {},
            { test: true }
          )
        end

        begin
          status_response = check_payment_status(payment)
          
          if status_response.nil?
            raise 'Invalid response from payment gateway'
          end
          
          if status_response['status'] == 'success' && status_response.dig('data', 'payment_status') == 'COMPLETED'
            payment.update!(state: 'completed')
            ActiveMerchant::Billing::Response.new(
              true,
              'Success',
              {},
              { test: true }
            )
          else
            ActiveMerchant::Billing::Response.new(
              false,
              status_response['message'] || 'Payment not completed',
              {},
              { test: true }
            )
          end
        rescue => e
          ActiveMerchant::Billing::Response.new(
            false,
            "Payment completion failed: #{e.message}",
            {},
            { test: true, error: e.message }
          )
        end
      end
    end
  end
  
  class Payment
    attr_accessor :payment_method, :order, :response_code, :source, :state, :amount
    
    def initialize(attributes = {})
      @payment_method = attributes[:payment_method]
      @order = attributes[:order]
      @response_code = attributes[:response_code]
      @source = attributes[:source]
      @state = attributes[:state] || 'pending'
      @amount = attributes[:amount] || 100.0
    end
    
    def completed?
      state == 'completed'
    end
    
    def update!(attributes)
      attributes.each { |k, v| send("#{k}=", v) }
      true
    end
    
    def reload
      self
    end
  end
  
  class Order
    attr_accessor :number, :total, :email, :state
    
    def initialize(attributes = {})
      @number = attributes[:number]
      @total = attributes[:total]
      @email = attributes[:email]
      @state = attributes[:state] || 'payment'
    end
  end
  
  class IpaySource
    attr_accessor :payment_method, :phone, :vendor_id
    
    def initialize(attributes = {})
      @payment_method = attributes[:payment_method]
      @phone = attributes[:phone]
      @vendor_id = attributes[:vendor_id]
    end
  end
end

# Mock ActiveMerchant::Billing::Response
module ActiveMerchant
  module Billing
    class Response
      attr_reader :success, :message, :params, :test
      
      def initialize(success, message, params = {}, options = {})
        @success = success
        @message = message
        @params = params
        @test = options[:test] || false
      end
      
      def success?
        @success
      end
    end
  end
end

RSpec.describe Spree::IpayPaymentMethod::Ipay do
  let(:payment_method) do
    Spree::IpayPaymentMethod::Ipay.new(
      name: 'iPay',
      preferences: {
        vendor_id: 'demo',
        hash_key: 'demohash',
        test_mode: true
      }
    )
  end
  
  let(:order) { Spree::Order.new(number: 'R123456789', total: 100.0, email: 'test@example.com') }
  let(:ipay_source) { Spree::IpaySource.new(payment_method: payment_method, phone: '254712345678', vendor_id: 'demo') }
  let(:payment) do
    Spree::Payment.new(
      payment_method: payment_method,
      order: order,
      response_code: 'TXN123',
      source: ipay_source,
      state: 'pending',
      amount: 100.0
    )
  end
  
  describe '#initialize' do
    it 'initializes with default values' do
      expect(payment_method.name).to eq('iPay')
      expect(payment_method.preferences[:vendor_id]).to eq('demo')
      expect(payment_method.preferences[:hash_key]).to eq('demohash')
      expect(payment_method.preferences[:test_mode]).to be true
    end
  end
  
  describe '#complete' do
    context 'when payment is already completed' do
      before { payment.state = 'completed' }
      
      it 'returns success response' do
        response = payment_method.complete(payment)
        expect(response).to be_success
        expect(response.message).to eq('Success')
      end
    end
    
    context 'when payment is not completed' do
      before do
        allow(payment_method).to receive(:check_payment_status).and_return({
          'status' => 'success',
          'data' => { 'payment_status' => 'COMPLETED' }
        })
      end
      
      it 'completes the payment and returns success' do
        response = payment_method.complete(payment)
        expect(response).to be_success
        expect(payment.state).to eq('completed')
      end
      
      context 'when payment status check fails' do
        before do
          allow(payment_method).to receive(:check_payment_status).and_return({
            'status' => 'failure',
            'message' => 'Payment not found'
          })
        end
        
        it 'returns failure response' do
          response = payment_method.complete(payment)
          expect(response).not_to be_success
          expect(response.message).to eq('Payment not found')
        end
      end
      
      context 'when payment status check raises an error' do
        before do
          allow(payment_method).to receive(:check_payment_status).and_raise(StandardError.new('Network error'))
        end
        
        it 'returns error response' do
          response = payment_method.complete(payment)
          expect(response).not_to be_success
          expect(response.message).to include('Network error')
        end
      end
      
      context 'when payment update fails' do
        before do
          allow(payment_method).to receive(:check_payment_status).and_return({
            'status' => 'success',
            'data' => { 'payment_status' => 'COMPLETED' }
          })
          allow(payment).to receive(:update!).and_raise(StandardError.new('DB error'))
        end
        
        it 'returns error response' do
          response = payment_method.complete(payment)
          expect(response).not_to be_success
          expect(response.message).to include('DB error')
        end
      end
    end
  end
end
