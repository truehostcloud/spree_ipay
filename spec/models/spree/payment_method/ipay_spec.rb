# frozen_string_literal: true

require '/home/symomkuu/spree_ipay/spec/rails_helper'

RSpec.describe Spree::PaymentMethod::Ipay, type: :model do
  let(:payment_method) { create(:payment_method_ipay, name: 'iPay', preferred_vendor_id: 'demo', preferred_hash_key: 'demohash') }
  let(:order) { create(:order) }
  let(:ipay_source) { create(:ipay_source, payment_method: payment_method) }
  let(:payment) { create(:payment, payment_method: payment_method, order: order, response_code: 'TXN123', source: ipay_source) }
  it 'is valid with valid attributes' do
    expect(described_class.new).to be_a(Spree::PaymentMethod::Ipay)
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
      expect(response.message).to eq('Success')
      expect(payment.reload.state).to eq('completed')
    end

    it 'returns failure response' do
      allow(payment_method).to receive(:check_payment_status).and_return({
        'status' => 'failure',
        'message' => 'Payment not completed'
      })
      response = payment_method.complete(payment)
      expect(response).not_to be_success
      expect(response.message).to eq('Payment not completed')
    end

    context 'when iPay returns failure status' do
      it 'returns failure response with message' do
        allow(payment_method).to receive(:check_payment_status).and_return({
          'status' => 'failure',
          'message' => 'Payment not completed'
        })
        response = payment_method.complete(payment)
        expect(response).not_to be_success
        expect(response.message).to eq('Payment not completed')
      end
    end

    context 'when iPay raises an exception' do
      it 'returns failure response with error message' do
        allow(payment_method).to receive(:check_payment_status).and_raise(StandardError.new('Network error'))
        response = payment_method.complete(payment)
        expect(response).not_to be_success
        expect(response.message).to match(/Payment completion failed: Network error/)
      end
    end

    context 'when iPay returns nil' do
      it 'returns failure response with generic message' do
        allow(payment_method).to receive(:check_payment_status).and_return(nil)
        response = payment_method.complete(payment)
        expect(response).not_to be_success
        expect(response.message).to match(/Payment completion failed: undefined method `\[\]' for nil/)
      end
    end

    context 'when payment is already completed' do
      it 'returns success immediately' do
        allow(payment).to receive(:completed?).and_return(true)
        response = payment_method.complete(payment)
        expect(response).to be_success
        expect(response.message).to eq('Success')
      end
    end

    context 'when payment update fails' do
      it 'returns failure response with error message' do
        allow(payment_method).to receive(:check_payment_status).and_return({
          'status' => 'success'
        })
        allow(payment).to receive(:completed?).and_return(false)
        allow(payment).to receive(:update!).and_raise(StandardError.new('DB error'))
        response = payment_method.complete(payment)
        expect(response).not_to be_success
        expect(response.message).to match(/Payment completion failed: DB error/)
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
        expect(response.message).to eq('Success')
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
        data_string = [
          payment_method.preferred_test_mode ? '0' : '1',
          order.number,
          order.number,
          payment.amount.to_f.round(2).to_s,
          '',
          order.email,
          payment_method.preferred_vendor_id,
          payment_method.preferred_currency.presence || 'KES',
          '', '', '', '',
          payment_method.preferred_callback_url.presence || '/ipay/confirm',
          '1',
          '2'
        ].join
        expected_hash = OpenSSL::HMAC.hexdigest('sha1', payment_method.preferred_hash_key, data_string)
        generated_hash = payment_method.send(:generate_hash, payment)
        expect(generated_hash).to eq(expected_hash)
      end
    end

    describe '#base_url' do
      context 'when in test mode' do
        it 'returns the shop root_url as base_url' do
          allow(Rails.application.routes.url_helpers).to receive(:root_url).and_return('https://myshop.example/')
          expect(payment_method.send(:base_url)).to eq('https://myshop.example')
        end
      end

      context 'when in live mode' do
        before { payment_method.update!(preferred_test_mode: false) }

        it 'returns the shop root_url as base_url' do
          allow(Rails.application.routes.url_helpers).to receive(:root_url).and_return('https://myshop.example/')
          expect(payment_method.send(:base_url)).to eq('https://myshop.example')
        end
      end
    end
  end
end