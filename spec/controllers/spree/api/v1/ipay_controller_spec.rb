# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Api::V1::IpayController, type: :controller do
  routes { Spree::Core::Engine.routes }

  let(:payment_method) do
    create(:payment_method, 
           type: 'Spree::PaymentMethod::Ipay',
           preferred_vendor_id: 'demo',
           preferred_hash_key: 'demohash')
  end
  
  let(:order) { create(:order_with_totals) }
  let(:payment) do
    create(:payment, 
           payment_method: payment_method, 
           order: order,
           response_code: 'TXN123')
  end

  describe 'POST #callback' do
    let(:valid_hash) do
      data_string = "#{payment_method.preferred_vendor_id}TXN123#{payment_method.preferred_hash_key}"
      Digest::SHA256.hexdigest(data_string)
    end

    context 'with valid callback' do
      before do
        allow_any_instance_of(Spree::PaymentMethod::Ipay).to receive(:complete).and_return(
          double(success?: true, message: 'Payment completed')
        )
      end

      it 'processes payment successfully' do
        post :callback, params: { payment_id: payment.id, hash: valid_hash }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['status']).to eq('success')
      end
    end

    context 'with invalid hash' do
      it 'returns unauthorized' do
        post :callback, params: { payment_id: payment.id, hash: 'invalid_hash' }
        
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['status']).to eq('failed')
      end
    end

    context 'with payment completion failure' do
      before do
        allow_any_instance_of(Spree::PaymentMethod::Ipay).to receive(:complete).and_return(
          double(success?: false, message: 'Payment failed')
        )
      end

      it 'returns unprocessable entity' do
        post :callback, params: { payment_id: payment.id, hash: valid_hash }
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['status']).to eq('failed')
      end
    end

    context 'with non-existent payment' do
      it 'returns not found' do
        post :callback, params: { payment_id: 99999, hash: valid_hash }
        
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['status']).to eq('error')
      end
    end
  end

  describe 'GET #return' do
    context 'when payment is completed' do
      before { payment.update!(state: 'completed') }

      it 'redirects to order page with success notice' do
        get :return, params: { payment_id: payment.id }
        
        expect(response).to redirect_to(spree.order_path(order))
        expect(flash[:notice]).to eq('Payment completed successfully!')
      end
    end

    context 'when payment is not completed' do
      before { payment.update!(state: 'pending') }

      it 'redirects to checkout payment page with error' do
        get :return, params: { payment_id: payment.id }
        
        expect(response).to redirect_to(spree.checkout_state_path(:payment))
        expect(flash[:alert]).to eq('Payment was not completed. Please try again.')
      end
    end

    context 'with non-existent payment' do
      it 'returns not found' do
        get :return, params: { payment_id: 99999 }
        
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET #status' do
    context 'with valid iPay payment' do
      before do
        allow_any_instance_of(Spree::PaymentMethod::Ipay).to receive(:check_payment_status).and_return({
          'status' => 'success',
          'data' => { 'payment_status' => 'COMPLETED' }
        })
      end

      it 'returns payment status' do
        get :status, params: { payment_id: payment.id }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['status']).to eq('success')
      end
    end

    context 'with non-iPay payment method' do
      let(:other_payment_method) { create(:payment_method) }
      let(:other_payment) { create(:payment, payment_method: other_payment_method) }

      it 'returns bad request' do
        get :status, params: { payment_id: other_payment.id }
        
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['status']).to eq('error')
      end
    end

    context 'with non-existent payment' do
      it 'returns not found' do
        get :status, params: { payment_id: 99999 }
        
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end