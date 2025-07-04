# frozen_string_literal: true

module Spree
  class IpayService
    include HTTParty

    def initialize(payment_method)
      @payment_method = payment_method
      @vendor_id = payment_method.preferred_vendor_id
      @hash_key = payment_method.preferred_hash_key
      @test_mode = payment_method.preferred_test_mode
    end

    def check_payment_status(transaction_id)
      query_data = {
        vid: @vendor_id,
        id: transaction_id,
        hsh: generate_status_hash(transaction_id)
      }

      response = self.class.post(
        status_check_url,
        body: query_data,
        headers: {
          'Content-Type' => 'application/x-www-form-urlencoded'
        },
        timeout: 30
      )

      if response.success?
        parse_status_response(response.body)
      else
        { success: false, message: 'Failed to check payment status' }
      end
    end

    private

    def generate_status_hash(transaction_id)
      hash_string = "#{@vendor_id}#{transaction_id}#{@hash_key}"
      Digest::SHA1.hexdigest(hash_string)
    end

    def status_check_url
      @test_mode ? 'https://sandbox.ipayafrica.com/ipn/' : 'https://www.ipayafrica.com/ipn/'
    end

    def parse_status_response(response_body)
      # Parse iPay status response
      # This will depend on iPay's actual response format
      {
        success: true,
        status: 'pending', # or 'completed', 'failed'
        data: response_body
      }
    end
  end
end
