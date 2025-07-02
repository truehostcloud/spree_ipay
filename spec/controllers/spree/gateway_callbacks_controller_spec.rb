require '/home/symomkuu/spree_ipay/spec/rails_helper'

RSpec.describe Spree::GatewayCallbacksController, type: :controller do
  routes { Spree::Core::Engine.routes }
  describe 'GET #confirm' do
    it 'responds successfully with valid params' do
      order = create(:order, total: 100.0)
      payment_method = create(:payment_method_ipay)
      ipay_source = create(:ipay_source, payment_method: payment_method)
      payment = create(:payment, order: order, payment_method: payment_method, source: ipay_source, amount: 100.0)

      params = {
        'order_id' => order.number,
        'status' => 'aei7p7yrx4ae34', # Success code
        'mc' => '100.0',
        'txnid' => 'TXN123',
        'live' => '0',
        'oid' => order.number,
        'inv' => order.number,
        'ttl' => '100.0',
        'tel' => '254712345678',
        'eml' => order.email,
        'vid' => payment_method.preferred_vendor_id,
        'curr' => 'KES',
        'p1' => '', 'p2' => '', 'p3' => '', 'p4' => '',
        'cbk' => '/ipay/confirm',
        'cst' => '1',
        'crl' => '2'
      }
      datastring = [params['live'], params['oid'], params['inv'], params['ttl'], params['tel'], params['eml'], params['vid'], params['curr'], params['p1'], params['p2'], params['p3'], params['p4'], params['cbk'], params['cst'], params['crl']].join
      hash_key = payment_method.preferred_hash_key
      params['hsh'] = OpenSSL::HMAC.hexdigest('sha1', hash_key, datastring)

      get :confirm, params: params
      expect(response).to be_successful
    end
  end
end
