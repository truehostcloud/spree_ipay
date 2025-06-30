# frozen_string_literal: true

require 'httparty'

module Spree
  class PaymentMethod::Ipay < PaymentMethod
    include HTTParty

    preference :vendor_id, :string
    preference :hash_key, :string
    preference :test_mode, :boolean, default: true
    preference :currency, :string, default: 'KES'
    preference :callback_url, :string, default: 'https://example.com/ipay/callback'
    preference :return_url, :string, default: 'https://example.com/ipay/return'
    
    # Channel preferences
    preference :mpesa, :boolean, default: true
    preference :bonga, :boolean, default: true
    preference :airtel, :boolean, default: true
    preference :equity, :boolean, default: true
    preference :mobilebanking, :boolean, default: true
    preference :creditcard, :boolean, default: true
    preference :unionpay, :boolean, default: true
    preference :mvisa, :boolean, default: true
    preference :vooma, :boolean, default: true
    preference :pesalink, :boolean, default: true
    preference :autopay, :boolean, default: true

    def payment_source_class
      Spree::IpaySource
    end

    def source_required?
      # We need to return true here to ensure a payment source is created
      # This is required for Spree's payment processing flow
      true
    end

    def auto_capture?
      false
    end

    def can_void?(payment)
      payment.pending? || payment.processing?
    end

    def can_capture?(payment)
      payment.pending? || payment.processing?
    end

    def supports?(source)
      # Return true for both nil source and IpaySource
      # This allows the payment to be created without a source initially
      source.nil? || source.is_a?(Spree::IpaySource)
    end

    def process_payment(payment)
      # First, authorize the payment
      response = authorize(
        payment.amount_in_cents, 
        payment.source, 
        originator: payment,
        order_id: payment.order.number
      )
      
      return response unless response.success?
      
      # If authorization is successful, capture the payment
      capture_response = capture(
        payment.amount_in_cents, 
        response.authorization, 
        originator: payment
      )
      
      return capture_response unless capture_response.success?
      
      # Update payment with the captured response
      payment.update!(
        state: 'completed',
        response_code: capture_response.authorization,
        avs_response: capture_response.avs_result['code']
      )
      
      capture_response
    rescue StandardError => e
      failure_response(e.message)
    end

    def authorize(amount, source, options = {})
      payment = options[:originator]
      order = payment.order
      
      # Ensure the order is in the correct state
      unless order.checkout_steps.include?('confirm')
        return failure_response("Order is not in a confirmable state")
      end
      
      # Ensure we have a valid source
      if source.blank? || !source.is_a?(Spree::IpaySource)
        return failure_response("Invalid payment source")
      end

      # Ensure source is associated with payment method
      if source.payment_method_id != id && !source.update(payment_method_id: id)
        return failure_response("Failed to update payment source")
      end
      
      # Get phone from source
      phone = source.phone
      
      # Store phone number in session if we have a controller context
      if options[:controller]&.respond_to?(:session)
        options[:controller].session[:ipay_phone_number] = phone
      end
      
      # Ensure payment has the source assigned
      if payment.source.nil? || !payment.source.is_a?(Spree::IpaySource)
        payment.source = source
        payment.payment_method_id = id
        
        # Save the payment to ensure source is associated
        unless payment.save
          return failure_response("Failed to save payment: #{payment.errors.full_messages.to_sentence}")
        end
      else
        payment.source.phone = phone
        if payment.source.changed? && !payment.source.save
          return failure_response("Failed to update payment source")
        end
      end
      
      # Process the payment
      process!(phone: phone, payment: payment, amount: amount, options: options)
    rescue => e
      failure_response("Authorization failed: #{e.message}")
    end

    def capture(amount, response_code, options = {})
      payment = options[:originator]
      
      # If we're in test mode, just return success
      if preferred_test_mode
        return ActiveMerchant::Billing::Response.new(
          true, 
          'Test mode - payment captured successfully', 
          { test: true, authorization: "TEST-#{SecureRandom.hex(8)}" }, 
          { test: true }
        )
      end
      
      # In production, you would implement the actual capture logic here
      # For now, we'll simulate a successful capture
      ActiveMerchant::Billing::Response.new(
        true, 
        'Payment captured successfully', 
        { authorization: response_code }, 
        {}
      )
    rescue => e
      failure_response("Capture failed: #{e.message}")
    end

    def void(response_code, options = {})
      payment = options[:originator]
      
      # If we're in test mode, just return success
      if preferred_test_mode
        return ActiveMerchant::Billing::Response.new(
          true, 
          'Test mode - payment voided successfully', 
          { test: true, authorization: "TEST-VOID-#{SecureRandom.hex(4)}" }, 
          { test: true }
        )
      end
      
      response = cancel_payment(response_code)
      
      if response['status'] == 'success'
        success_response
      else
        failure_response(response['message'] || 'Payment void failed')
      end
    rescue => e
      failure_response("Payment void failed: #{e.message}")
    end

    def process!(phone: nil, payment: nil, amount: nil, options: {})
      # Process iPay payment
      
      begin
        # Validate required parameters
        unless phone.present? && payment.present? && payment.order.present? && amount.present?
          error_msg = "Missing required parameters for iPay payment"
          payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
          return failure_response(error_msg)
        end

        # Validate phone number format
        unless phone.to_s.match(/^\+?\d{10,15}$/)
          error_msg = "Invalid phone number format: #{phone}"
          payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
          return failure_response('Please enter a valid phone number')
        end

        # Validate payment amount
        unless amount.to_f > 0
          error_msg = "Invalid payment amount: #{amount}"
          payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
          return failure_response('Invalid payment amount')
        end

        # Validate iPay credentials
        vendor_id = preferred_vendor_id.presence || SpreeIpay::Preferences.vendor_id
        hash_key = preferred_hash_key.presence || SpreeIpay::Preferences.secret_key
        
        unless vendor_id.present? && hash_key.present?
          error_msg = "Missing iPay credentials. Please configure vendor_id and hash_key."
          payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
          return failure_response('Payment configuration error. Please contact support.')
        end

        # Update payment amount if needed
        if payment.amount.to_f != amount.to_f
          payment.amount = amount
          payment.save!
        end

        # Store phone number in session if we have a controller context
        if options[:controller]&.respond_to?(:session)
          options[:controller].session[:ipay_phone_number] = phone
        end

        # Transition payment to processing state
        payment.started_processing! if payment.respond_to?(:started_processing!)
        
        # Payment processing started
        payment.log_entries.create(details: 'Payment processing started') if payment.respond_to?(:log_entries)
        
        # Return success response
        success_response('Payment processing started')
        
      rescue => e
        error_msg = "Payment processing failed: #{e.message}"
        payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
        failure_response(error_msg)
      end
    end

    # Generate HMAC SHA1 hash for iPay
    def ipay_signature_hash(payment)
      # Get values from payment method preferences
      vendor_id = preferred_vendor_id.to_s
      hash_key = preferred_hash_key.to_s
      
      # Validate required preferences
      if vendor_id.blank? || hash_key.blank?
        raise "Missing required iPay credentials. Please configure vendor_id and hash_key in payment method settings."
      end
      
      # Get required values
      live = test_mode? ? "0" : "1"
      oid = payment.order.number.to_s
      inv = "#{payment.order.number}#{Time.now.to_i}" # unique invoice
      ttl = (payment.amount.to_f * 100).to_i.to_s  # Amount in cents
      tel = payment.order.bill_address&.phone.to_s || session[:ipay_phone_number].to_s || "0700000000"
      eml = payment.order.email.to_s
      vid = vendor_id
      curr = preferred_currency.presence || 'KES'
      p1 = ""
      p2 = ""
      p3 = ""
      p4 = ""
      cbk = preferred_callback_url.presence || "https://example.com/ipay/callback"
      rst = preferred_return_url.presence || "https://example.com/ipay/return"
      cst = "1"
      crl = "2"

      # Ensure all values are strings and not nil
      [live, oid, inv, ttl, tel, eml, vid, curr, p1, p2, p3, p4, cbk, rst, cst, crl].each do |param|
        raise "Nil parameter in hash generation" if param.nil?
      end

      # Concatenate datastring in the required order
      datastring = "#{live}#{oid}#{inv}#{ttl}#{tel}#{eml}#{vid}#{curr}#{p1}#{p2}#{p3}#{p4}#{cbk}#{cst}#{crl}"

      # Generate hash using HMAC SHA1
      OpenSSL::HMAC.hexdigest('sha1', hash_key, datastring)
    rescue => e
      raise "Error generating hash: #{e.message}"
    end

    def generate_ipay_form_html(payment)
      # Get required values
      live = test_mode? ? "0" : "1"
      # Use numeric order ID for transaction code
      oid = payment.order.id.to_s
      # Use numeric order ID for invoice as well
      inv = payment.order.id.to_s
      ttl = (payment.amount.to_f * 100).to_i.to_s  # Amount in cents
      tel = payment.order.bill_address&.phone || session[:ipay_phone_number] || "0700000000"
      eml = payment.order.email
      vid = preferred_vendor_id
      curr = preferred_currency.presence || 'KES'
      p1 = ""
      p2 = ""
      p3 = ""
      p4 = ""
      # Generate proper callback and return URLs
      # Extract host from the return_url preference
      return_uri = URI.parse(preferred_return_url.presence || 'https://example.com')
      default_host = return_uri.host
      default_protocol = return_uri.scheme || 'https'
      
      # Generate callback URL for iPay to send payment status
      begin
        if preferred_callback_url.present?
          callback_uri = URI.parse(preferred_callback_url)
          callback_uri.scheme ||= default_protocol
          callback_uri.host ||= default_host
          callback_uri.path = '/api/v1/ipay/callback' if callback_uri.path.blank? || callback_uri.path == '/'
        else
          # In test mode, ensure we're using HTTPS for security
          protocol = test_mode? ? 'https' : default_protocol
          callback_uri = URI.parse("#{protocol}://#{default_host}/api/v1/ipay/callback")
        end
        
        # Ensure the callback URL is valid
        raise URI::InvalidURIError if callback_uri.host.blank?
        
        # Add test parameter if in test mode
        if test_mode?
          params = URI.decode_www_form(callback_uri.query || '').to_h
          params['test'] = '1'
          callback_uri.query = URI.encode_www_form(params)
        end
        
        cbk = callback_uri.to_s
      rescue URI::InvalidURIError => e
          # Fallback to a safe default in case of errors
        cbk = "https://#{default_host}/api/v1/ipay/callback"
        cbk += '?test=1' if test_mode?
      end
      
      # Generate return URL for customer redirect after payment
      # Point to the frontend order confirmation page
      order_number = payment.order.number
      order_token = payment.order.guest_token
      rst = preferred_return_url.presence || "#{default_protocol}://#{default_host}/orders/#{order_number}?order_token=#{order_token}"
      
      cst = "1"  # Customer email notification flag
      crl = "2"  # Customer phone notification flag
      
      begin
        hsh = ipay_signature_hash(payment)
      rescue => e
        raise "Error generating payment hash: #{e.message}"
      end

      # Prepare iPay parameters
      ipay_params = {
        live: live,
        oid: oid,
        inv: inv,
        ttl: ttl,
        tel: tel,
        eml: eml,
        vid: vid,
        curr: curr,
        p1: p1,
        p2: p2,
        p3: p3,
        p4: p4,
        cbk: cbk,
        rst: rst,
        cst: cst,
        crl: crl,
        hsh: hsh
      }


      # Add channel parameters based on preferences
      [
        :mpesa, :bonga, :airtel, :equity, :mobilebanking,
        :creditcard, :unionpay, :mvisa, :vooma, :pesalink, :autopay
      ].each do |channel|
        ipay_params[channel] = self.preferences[channel.to_s] ? '1' : '0'
      end



      # Generate form HTML
      form_html = "<form id='ipay_form' action='https://payments.ipayafrica.com/v3/ke' method='POST'>\n"
      
      # Add all parameters with proper escaping
      ipay_params.each do |key, value|
        form_html << "  <input type='hidden' name='#{key}' value='#{ERB::Util.html_escape(value.to_s)}'>\n"
      end
      
      # Add submit button and auto-submit script
      form_html << "  <input type='submit' value='Pay with iPay'>\n"
      form_html << "</form>\n"
      form_html << "<script>document.getElementById('ipay_form').submit();</script>\n"
      
      form_html
    end

    def confirm(payment, phone: nil)
      return success_response if payment.completed?

      begin
        response = initiate_payment(payment, phone: phone)

        if response['status'] == 'success'
          payment.update!(
            response_code: response['data']['transaction_id'],
            avs_response: response['data']['checkout_url']
          )

          ActiveMerchant::Billing::Response.new(
            true,
            'Payment confirmation initiated successfully',
            response,
            {
              authorization: response['data']['transaction_id'],
              test: test_mode?,
              checkout_url: response['data']['checkout_url']
            }
          )
        else
          failure_response(response['message'] || 'Payment confirmation failed')
        end
      rescue => e
        failure_response("Payment confirmation failed: #{e.message}")
      end
    end

    def complete(payment)
      return success_response if payment.completed?

      begin
        # Check payment status
        status = check_payment_status(payment.response_code)
        
        if status['status'] == 'success'
          payment.update!(state: 'completed')
          success_response
        else
          failure_response(status['message'] || 'Payment completion failed')
        end
      rescue => e
        failure_response("Payment completion failed: #{e.message}")
      end
    end

    def void(response_code, options = {})
      begin
        response = cancel_payment(response_code)
        
        if response['status'] == 'success'
          success_response
        else
          failure_response(response['message'] || 'Payment void failed')
        end
      rescue => e
        failure_response("Payment void failed: #{e.message}")
      end
    end

    def initiate_payment(payment, phone: nil)
      # Prepare parameters
      params = {
        live: test_mode? ? '0' : '1',
        oid: payment.order.number,
        inv: payment.order.number,
        ttl: payment.amount.to_f.round(2).to_s,
        tel: phone,
        eml: payment.order.email,
        vid: SpreeIpay::Preferences.vendor_id,
        curr: SpreeIpay::Preferences.currency,
        p1: '',
        p2: '',
        p3: '',
        p4: '',
        cbk: SpreeIpay::Preferences.callback_url,
        cst: '1',
        crl: '2',
        hsh: generate_hash(payment)
      }


      # Add channel parameters
      [
        :mpesa, :bonga, :airtel, :equity, :mobilebanking,
        :creditcard, :unionpay, :mvisa, :vooma, :pesalink, :autopay
      ].each do |channel|
        params[channel.to_s] = SpreeIpay::Preferences.send(channel) ? '1' : '0'
      end

      # Generate form HTML
      form_html = "<form id='ipay_form' action='#{SpreeIpay::Preferences.api_endpoint}' method='post'>"
      params.each do |key, value|
        form_html += "<input type='hidden' name='#{key}' value='#{ERB::Util.html_escape(value)}'>"
      end
      form_html += "<button type='submit' style='display:none'>Pay</button></form>"
      form_html += "<script>document.getElementById('ipay_form').submit();</script>"

      # Store form HTML in session
      options[:controller].session[:ipay_form_html] = form_html

      # Return success response
      ActiveMerchant::Billing::Response.new(
        true,
        'iPay payment initiated successfully',
        {
          form_html: form_html
        }
      )
    rescue => e
      failure_response("Payment initiation failed: #{e.message}")
    end

    def check_payment_status(transaction_id)
      # Prepare status check parameters
      params = {
        live: test_mode? ? '0' : '1',
        vid: SpreeIpay::Preferences[:vendor_id],
        tid: transaction_id,
        hsh: generate_status_hash(transaction_id)
      }

      # Make API call to check status
      response = HTTParty.post(
        SpreeIpay::Preferences[:api_endpoint],
        body: params
      )

      # Parse and return response
      JSON.parse(response.body)
    rescue => e
      {
        status: 'error',
        message: "Failed to check payment status: #{e.message}"
      }
    end

    def cancel_payment(transaction_id)
      # Prepare cancellation parameters
      params = {
        live: test_mode? ? '0' : '1',
        vid: SpreeIpay::Preferences[:vendor_id],
        tid: transaction_id,
        hsh: generate_cancel_hash(transaction_id)
      }

      # Make API call to cancel payment
      response = HTTParty.post(
        SpreeIpay::Preferences.api_endpoint,
        body: params
      )

      # Parse and return response
      JSON.parse(response.body)
    rescue => e
      {
        status: 'error',
        message: "Failed to cancel payment: #{e.message}"
      }
    end

    def generate_hash(payment)
      # Generate hash based on iPay's requirements
      data_string = [
        SpreeIpay::Preferences.live_mode ? '1' : '0',
        payment.order.id.to_s,  # Use numeric order ID
        payment.order.id.to_s,  # Use numeric order ID for both oid and inv
        payment.amount.to_f.round(2).to_s,
        payment.order.email,
        SpreeIpay::Preferences.vendor_id,
        SpreeIpay::Preferences.currency,
        '', # p1
        '', # p2
        '', # p3
        '', # p4
        SpreeIpay::Preferences.callback_url,
        '1', # cst
        '2'  # crl
      ].join

      # Generate and return hash using HMAC SHA1
      OpenSSL::HMAC.hexdigest('sha1', SpreeIpay::Preferences.secret_key, data_string)
    end

    def generate_status_hash(transaction_id)
      # Generate hash for status check
      data_string = [
        SpreeIpay::Preferences.live_mode ? '1' : '0',
        SpreeIpay::Preferences.vendor_id,
        transaction_id
      ].join

      # Generate and return hash using HMAC SHA1
      OpenSSL::HMAC.hexdigest('sha1', SpreeIpay::Preferences.secret_key, data_string)
    end

    def generate_cancel_hash(transaction_id)
      # Generate hash for cancellation
      data_string = [
        SpreeIpay::Preferences.live_mode ? '1' : '0',
        SpreeIpay::Preferences.vendor_id,
        transaction_id
      ].join

      # Generate and return hash using HMAC SHA1
      OpenSSL::HMAC.hexdigest('sha1', SpreeIpay::Preferences.secret_key, data_string)
    end

    def callback_url(payment)
      "#{base_url}/ipay/callback?order=#{payment.order.number}"
    end

    def return_url(payment)
      "#{base_url}/ipay/return?order=#{payment.order.number}"
    end

    def base_url
      Rails.application.routes.url_helpers.root_url.chomp('/')
    end

    def test_mode?
      SpreeIpay::Preferences.test_mode
    end
    
    def source_required?
      true
    end

    def success_response(message = 'Success')
      ActiveMerchant::Billing::Response.new(
        true,
        message,
        {},
        test: test_mode?
      )
    end

    def failure_response(message = 'Failed')
      ActiveMerchant::Billing::Response.new(
        false,
        message,
        {},
        test: test_mode?
      )
    end
  end
end
