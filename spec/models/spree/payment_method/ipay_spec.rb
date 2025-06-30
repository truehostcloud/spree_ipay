# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::PaymentMethod::Ipay, type: :model do
  let(:payment_method) do
    described_class.create!(
      name: 'iPay',
      preferred_vendor_id: 'demo',
      preferred_hash_key: 'demohash',
      preferred_test_mode: true
    )
  end

  let(:order) { create(:order_with_totals) }
  let(:payment) do
    create(:payment, 
           payment_method: payment_method, 
           order: order,
           amount: order.total)
  end

  describe '#payment_source_class' do
    it 'returns nil' do
      expect(payment_method.payment_source_class).to be_nil
    end
  end

  describe '#source_required?' do
    it 'returns false' do
      expect(payment_method.source_required?).to be false
    end
  end

  describe '#auto_capture?' do
    it 'returns false' do
      expect(payment_method.auto_capture?).to be false
    end
  end

  describe '#supports?' do
    it 'supports nil source' do
      expect(payment_method.supports?(nil)).to be true
    end
  end

  describe '#confirm' do
    context 'when payment is already completed' do
      before { payment.update!(state: 'completed') }

      it 'returns success response' do
        response = payment_method.confirm(payment)
        expect(response).to be_success
      end
    end

    context 'when initiating new payment' do
      before do
        allow(payment_method).to receive(:initiate_payment).and_return({
          'status' => 'success',
          'data' => {
            'transaction_id' => 'TXN123',
            'checkout_url' => 'https://example.com/checkout'
          }
        })
      end

      it 'initiates payment and returns success response' do
        response = payment_method.confirm(payment)
        
        expect(response).to be_success
        expect(response.authorization).to eq('TXN123')
        expect(response.params[:checkout_url]).to eq('https://example.com/checkout')
        expect(payment.response_code).to eq('TXN123')
      end
    end

    context 'when initiation fails' do
      before do
        allow(payment_method).to receive(:initiate_payment).and_return({
          'status' => 'error',
          'message' => 'Invalid credentials'
        })
      end

      it 'returns failure response' do
        response = payment_method.confirm(payment)
        
        expect(response).not_to be_success
        expect(response.message).to eq('Invalid credentials')
      end
    end
  end

  describe '#complete' do
    before { payment.update!(response_code: 'TXN123') }

    context 'when payment is already completed' do
      before { payment.update!(state: 'completed') }

      it 'returns success response' do
        response = payment_method.complete(payment)
        expect(response).to be_success
      end
    end

    context 'when payment status is completed' do
      before do
        allow(payment_method).to receive(:check_payment_status).and_return({
          'status' => 'success',
          'data' => { 'payment_status' => 'COMPLETED' }
        })
      end

      it 'completes payment and returns success response' do
        response = payment_method.complete(payment)
        
        expect(response).to be_success
        expect(response.message).to eq('Payment completed successfully')
        expect(payment.reload.state).to eq('completed')
      end
    end

    context 'when payment is not completed' do
      before do
        allow(payment_method).to receive(:check_payment_status).and_return({
          'status' => 'success',
          'data' => { 'payment_status' => 'PENDING' }
        })
      end

      it 'returns failure response' do
        response = payment_method.complete(payment)
        
        expect(response).not_to be_success
        expect(response.message).to eq('Payment not completed')
      end
    end
  end

  describe '#void' do
    let(:response_code) { 'TXN123' }

    context 'when void is successful' do
      before do
        allow(payment_method).to receive(:cancel_payment).and_return({
          'status' => 'success'
        })
      end

      it 'returns success response' do
        response = payment_method.void(response_code, {})
        
        expect(response).to be_success
        expect(response.message).to eq('Payment voided successfully')
      end
    end

    context 'when void fails' do
      before do
        allow(payment_method).to receive(:cancel_payment).and_return({
          'status' => 'error',
          'message' => 'Cannot void completed payment'
        })
      end

      it 'returns failure response' do
        response = payment_method.void(response_code, {})
        
        expect(response).not_to be_success
        expect(response.message).to eq('Cannot void completed payment')
      end
    end
  end

  describe 'private methods' do
    describe '#generate_hash' do
      it 'generates correct hash for payment' do
        expected_data = "#{payment_method.preferred_vendor_id}#{payment.amount.to_f}#{payment.currency}#{order.number}#{payment_method.preferred_hash_key}"
        expected_hash = Digest::SHA256.hexdigest(expected_data)
        
        generated_hash = payment_method.send(:generate_hash, payment)
        expect(generated_hash).to eq(expected_hash)
      end
    end

    describe '#base_url' do
      context 'when in test mode' do
        it 'returns sandbox URL' do
          expect(payment_method.send(:base_url)).to eq('https://sandbox.ipayafrica.com/v3/ke')
        end
      end

      context 'when in live mode' do
        before { payment_method.update!(preferred_test_mode: false) }

        it 'returns production URL' do
          expect(payment_method.send(:base_url)).to eq('https://payments.ipayafrica.com/v3/ke')
        end
      end
    end
  end
end