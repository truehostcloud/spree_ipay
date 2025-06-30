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
      Rails.logger.info "\nOMKUU [IPay#process_payment] Starting payment processing"
      
      # First, authorize the payment
      response = authorize(
        payment.amount_in_cents, 
        payment.source, 
        originator: payment,
        order_id: payment.order.number
      )
      
      unless response.success?
        Rails.logger.error "OMKUU [IPay#process_payment] Authorization failed: #{response.message}"
        return response
      end
      
      # If authorization is successful, capture the payment
      capture_response = capture(
        payment.amount_in_cents, 
        response.authorization, 
        originator: payment
      )
      
      unless capture_response.success?
        Rails.logger.error "OMKUU [IPay#process_payment] Capture failed: #{capture_response.message}"
        return capture_response
      end
      
      # Update payment with the captured response
      payment.update!(
        state: 'completed',
        response_code: capture_response.authorization,
        avs_response: capture_response.avs_result['code']
      )
      
      Rails.logger.info "OMKUU [IPay#process_payment] Payment processed successfully"
      capture_response
    rescue StandardError => e
      Rails.logger.error "OMKUU [IPay#process_payment] Error: #{e.message}"
      failure_response(e.message)
    end

    def authorize(amount, source, options = {})
      Rails.logger.info "\nOMKUU [IPay#authorize] Starting authorization"
      Rails.logger.info "OMKUU [IPay#authorize] Options: #{options.except(:controller).inspect}"
      
      payment = options[:originator]
      order = payment.order
      
      Rails.logger.info "OMKUU [IPay#authorize] Processing Order ##{order.number}, Payment ID: #{payment.id}"
      Rails.logger.info "OMKUU [IPay#authorize] Current payment state: #{payment.state}"
      Rails.logger.info "OMKUU [IPay#authorize] Source provided: #{source.inspect}"
      
      # Ensure the order is in the correct state
      unless order.checkout_steps.include?('confirm')
        error_msg = "Order is not in a confirmable state"
        Rails.logger.error "OMKUU [IPay#authorize] ERROR: #{error_msg}"
        return failure_response(error_msg)
      end
      
      # Ensure we have a valid source
      if source.blank? || !source.is_a?(Spree::IpaySource)
        error_msg = "Invalid payment source: #{source.inspect}"
        Rails.logger.error "OMKUU [IPay#authorize] ERROR: #{error_msg}"
        Rails.logger.error "OMKUU [IPay#authorize] Source class: #{source.class.name} (expected Spree::IpaySource)"
        return failure_response(error_msg)
      end
      
      Rails.logger.info "OMKUU [IPay#authorize] Source is valid: ID=#{source.id}, Phone=#{source.phone}"

      # Ensure source is associated with payment method
      if source.payment_method_id != id
        Rails.logger.info "OMKUU [IPay#authorize] Updating source payment_method_id from #{source.payment_method_id} to #{id}"
        if source.update(payment_method_id: id)
          Rails.logger.info "OMKUU [IPay#authorize] Successfully updated source payment_method_id"
        else
          error_msg = "Failed to update source: #{source.errors.full_messages.to_sentence}"
          Rails.logger.error "OMKUU [IPay#authorize] ERROR: #{error_msg}"
          return failure_response(error_msg)
        end
      end
      
      # Get phone from source
      phone = source.phone
      Rails.logger.info "OMKUU [IPay#authorize] Using phone: #{phone}"
      
      # Store phone number in session if we have a controller context
      if options[:controller]&.respond_to?(:session)
        options[:controller].session[:ipay_phone_number] = phone
        Rails.logger.info "OMKUU [IPay#authorize] Stored phone number in session"
      end
      
      # Log payment source state
      Rails.logger.info "OMKUU [IPay#authorize] Payment source before assignment: #{payment.source.inspect}"
      Rails.logger.info "OMKUU [IPay#authorize] Payment source_id before assignment: #{payment.source_id}"
      
      # Ensure payment has the source assigned
      if payment.source.nil? || !payment.source.is_a?(Spree::IpaySource)
        Rails.logger.info "OMKUU [IPay#authorize] Assigning new source to payment"
        payment.source = source
        payment.payment_method_id = id
        
        # Save the payment to ensure source is associated
        if payment.save
          Rails.logger.info "OMKUU [IPay#authorize] Successfully saved payment with source"
          Rails.logger.info "OMKUU [IPay#authorize] Updated payment source: #{payment.source.inspect}"
          Rails.logger.info "OMKUU [IPay#authorize] Updated payment source_id: #{payment.source_id}"
          Rails.logger.info "OMKUU Created new IpaySource for payment #{payment.id}"
        else
          error_msg = "Failed to save payment: #{payment.errors.full_messages.to_sentence}"
          Rails.logger.error "OMKUU [IPay#authorize] ERROR: #{error_msg}"
          return failure_response(error_msg)
        end
      else
        Rails.logger.info "OMKUU [IPay#authorize] Payment already has a valid source"
        payment.source.phone = phone
        if payment.source.changed?
          if payment.source.save
            Rails.logger.info "OMKUU Updated phone number for existing IpaySource"
          else
            error_msg = "Failed to update source: #{payment.source.errors.full_messages.to_sentence}"
            Rails.logger.error "OMKUU [IPay#authorize] ERROR: #{error_msg}"
            return failure_response(error_msg)
          end
        end
        Rails.logger.info "OMKUU Using existing IpaySource for payment #{payment.id}"
      end
      
      # Process the payment
      process!(phone: phone, payment: payment, amount: amount, options: options)
    rescue => e
      error_msg = "Authorization failed: #{e.message}"
      Rails.logger.error "OMKUU #{error_msg}"
      Rails.logger.error e.backtrace.join("\n")
      failure_response(error_msg)
    end

    def capture(amount, response_code, options = {})
      Rails.logger.info "\nOMKUU [IPay#capture] Starting capture"
      Rails.logger.info "OMKUU [IPay#capture] Amount: #{amount}, Response Code: #{response_code}"
      
      payment = options[:originator]
      order = payment.order
      
      # If we're in test mode, just authorize the payment
      if preferred_test_mode
        Rails.logger.info "OMKUU [IPay#capture] Test mode - simulating successful capture"
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
    rescue StandardError => e
      Rails.logger.error "OMKUU [IPay#capture] Error: #{e.message}"
      failure_response(e.message)
    end

    def void(response_code, options = {})
      Rails.logger.info "OMKUU Voiding payment for response code: #{response_code}"
      
      begin
        response = cancel_payment(response_code)
        
        if response['status'] == 'success'
          Rails.logger.info "OMKUU Payment voided successfully"
          success_response
        else
          Rails.logger.error "OMKUU Payment void failed: #{response['message']}"
          failure_response(response['message'])
        end
      rescue => e
        Rails.logger.error "OMKUU Payment void error: #{e.message}"
        Rails.logger.error "OMKUU Error backtrace: #{e.backtrace.join("\n")}"
        failure_response("Payment void failed: #{e.message}")
      end
    end

    def process!(phone: nil, payment: nil, amount: nil, options: {})
      Rails.logger.info "OMKUU Starting iPay payment processing for Order #{payment.order.number}"
      
      begin
        # Validate required parameters
        unless phone.present? && payment.present? && payment.order.present? && amount.present?
          error_msg = "Missing required parameters for iPay payment"
          Rails.logger.error "OMKUU #{error_msg}"
          payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
          return failure_response(error_msg)
        end

        # Validate phone number format
        unless phone.to_s.match(/^\+?\d{10,15}$/)
          error_msg = "Invalid phone number format: #{phone}"
          Rails.logger.error "OMKUU #{error_msg}"
          payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
          return failure_response('Please enter a valid phone number')
        end

        # Validate payment amount
        unless amount.to_f > 0
          error_msg = "Invalid payment amount: #{amount}"
          Rails.logger.error "OMKUU #{error_msg}"
          payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
          return failure_response('Invalid payment amount')
        end

        # Validate iPay credentials
        vendor_id = preferred_vendor_id.presence || SpreeIpay::Preferences.vendor_id
        hash_key = preferred_hash_key.presence || SpreeIpay::Preferences.secret_key
        
        unless vendor_id.present? && hash_key.present?
          error_msg = "Missing iPay credentials. Please configure vendor_id and hash_key."
          Rails.logger.error "OMKUU #{error_msg}"
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
        
        # Log successful processing
        Rails.logger.info "OMKUU Successfully processed payment for Order #{payment.order.number}"
        payment.log_entries.create(details: 'Payment processing started') if payment.respond_to?(:log_entries)
        
        # Return success response
        success_response('Payment processing started')
        
      rescue => e
        error_msg = "Payment processing failed: #{e.message}"
        Rails.logger.error "OMKUU #{error_msg}"
        Rails.logger.error "OMKUU Error backtrace: #{e.backtrace.join("\n")}"
        payment.log_entries.create(details: error_msg) if payment.respond_to?(:log_entries)
        failure_response(error_msg)
      end
    end

    # Generate HMAC SHA1 hash for iPay using the working implementation
    def ipay_signature_hash(payment)
      Rails.logger.info "OMKUU Starting hash generation for Order #{payment&.order&.number}"
      
      # Debug log all preferences and payment details
      Rails.logger.info "OMKUU Payment object: #{payment.inspect}"
      Rails.logger.info "OMKUU Payment order: #{payment.order.inspect if payment&.order}"
      
      # Get values from payment method preferences
      vendor_id = preferred_vendor_id.to_s
      hash_key = preferred_hash_key.to_s
      
      Rails.logger.info "OMKUU Vendor ID from preferences: #{vendor_id.inspect}"
      Rails.logger.info "OMKUU Hash Key from preferences: #{hash_key.present? ? '[PRESENT]' : '[MISSING]'}"
      
      # Validate required preferences
      if vendor_id.blank? || hash_key.blank?
        error_msg = "Missing required iPay credentials. Please configure vendor_id and hash_key in payment method settings."
        Rails.logger.error "OMKUU #{error_msg}"
        raise error_msg
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
        if param.nil?
          Rails.logger.error "OMKUU Found nil parameter in hash generation"
          raise "Nil parameter in hash generation"
        end
      end

      # Concatenate datastring in the required order
      datastring = "#{live}#{oid}#{inv}#{ttl}#{tel}#{eml}#{vid}#{curr}#{p1}#{p2}#{p3}#{p4}#{cbk}#{cst}#{crl}"
      Rails.logger.info "OMKUU Data string for hash: #{datastring}"

      begin
        # Generate hash using HMAC SHA1
        hash = OpenSSL::HMAC.hexdigest('sha1', hash_key, datastring)
        Rails.logger.info "OMKUU Generated hash: #{hash}"
        hash
      rescue => e
        Rails.logger.error "OMKUU Error generating hash: #{e.message}"
        raise "Error generating hash: #{e.message}"
      end
    end

    def generate_ipay_form_html(payment)
      # Get required values
      live = test_mode? ? "0" : "1"
      oid = payment.order.number
      inv = "#{payment.order.number}#{Time.now.to_i}" # unique invoice
      ttl = (payment.amount.to_f * 100).to_i.to_s  # Amount in cents
      tel = payment.order.bill_address&.phone || session[:ipay_phone_number] || "0700000000"
      eml = payment.order.email
      vid = preferred_vendor_id
      curr = preferred_currency.presence || 'KES'
      p1 = ""
      p2 = ""
      p3 = ""
      p4 = ""
      cbk = preferred_callback_url.presence || "https://example.com/ipay/callback"
      rst = preferred_return_url.presence || "https://example.com/ipay/return"
      cst = "1"
      crl = "2"
      hsh = ipay_signature_hash(payment)

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

      Rails.logger.info "OMKUU iPay API request parameters: #{ipay_params.inspect}"

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
        Rails.logger.info "OMKUU Confirming payment for Order ##{payment.order.number}"
        response = initiate_payment(payment, phone: phone)

        if response['status'] == 'success'
          Rails.logger.info "OMKUU Payment confirmed successfully for Order ##{payment.order.number}"
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
          Rails.logger.warn "OMKUU Payment confirmation failed for Order ##{payment.order.number}: #{response['message']}"
          failure_response(response['message'] || 'Payment confirmation failed')
        end
      rescue => e
        Rails.logger.error "OMKUU Payment confirmation error: #{e.message}"
        Rails.logger.error "OMKUU Error backtrace: #{e.backtrace.join("\n")}"
        failure_response("Payment confirmation failed: #{e.message}")
      end
    end

    def complete(payment)
      Rails.logger.info "OMKUU Completing payment for Order ##{payment.order.number}"
      
      if payment.completed?
        Rails.logger.info "OMKUU Payment already completed"
        return success_response
      end

      begin
        # Check payment status
        status = check_payment_status(payment.response_code)
        
        if status['status'] == 'success'
          Rails.logger.info "OMKUU Payment completed successfully"
          payment.update!(state: 'completed')
          success_response
        else
          Rails.logger.error "OMKUU Payment completion failed: #{status['message']}"
          failure_response(status['message'])
        end
      rescue => e
        Rails.logger.error "OMKUU Payment completion error: #{e.message}"
        Rails.logger.error "OMKUU Error backtrace: #{e.backtrace.join("\n")}"
        failure_response("Payment completion failed: #{e.message}")
      end
    end

    def void(response_code, options = {})
      Rails.logger.info "OMKUU Voiding payment for response code: #{response_code}"
      
      begin
        response = cancel_payment(response_code)
        
        if response['status'] == 'success'
          Rails.logger.info "OMKUU Payment voided successfully"
          success_response
        else
          Rails.logger.error "OMKUU Payment void failed: #{response['message']}"
          failure_response(response['message'])
        end
      rescue => e
        Rails.logger.error "OMKUU Payment void error: #{e.message}"
        Rails.logger.error "OMKUU Error backtrace: #{e.backtrace.join("\n")}"
        failure_response("Payment void failed: #{e.message}")
      end
    end

    def initiate_payment(payment, phone: nil)
      Rails.logger.info "OMKUU Initiating payment for Order ##{payment.order.number}"
      
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
      Rails.logger.error "OMKUU Payment initiation failed: #{e.message}"
      Rails.logger.error "OMKUU Error backtrace: #{e.backtrace.join("\n")}"
      failure_response("Payment initiation failed: #{e.message}")
    end

    def check_payment_status(transaction_id)
      Rails.logger.info "OMKUU Checking payment status for transaction: #{transaction_id}"
      
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

      # Parse response
      status = JSON.parse(response.body)
      
      Rails.logger.info "OMKUU Payment status response: #{status.inspect}"
      status
    rescue => e
      Rails.logger.error "OMKUU Payment status check failed: #{e.message}"
      Rails.logger.error "OMKUU Error backtrace: #{e.backtrace.join("\n")}"
      {
        status: 'error',
        message: "Failed to check payment status: #{e.message}"
      }
    end

    def cancel_payment(transaction_id)
      Rails.logger.info "OMKUU Cancelling payment for transaction: #{transaction_id}"
      
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

      # Parse response
      status = JSON.parse(response.body)
      
      Rails.logger.info "OMKUU Payment cancellation response: #{status.inspect}"
      status
    rescue => e
      Rails.logger.error "OMKUU Payment cancellation failed: #{e.message}"
      Rails.logger.error "OMKUU Error backtrace: #{e.backtrace.join("\n")}"
      {
        status: 'error',
        message: "Failed to cancel payment: #{e.message}"
      }
    end

    def generate_hash(payment)
      # Generate hash based on iPay's requirements
      data_string = [
        SpreeIpay::Preferences.live_mode ? '1' : '0',
        payment.order.number,
        payment.order.number,
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

      Rails.logger.info "OMKUU Data string for hash: #{data_string}"

      # Generate hash using HMAC SHA1
      hash = OpenSSL::HMAC.hexdigest('sha1', SpreeIpay::Preferences.secret_key, data_string)
      
      Rails.logger.info "OMKUU Generated hash: #{hash}"
      hash
    end

    def generate_status_hash(transaction_id)
      # Generate hash for status check
      data_string = [
        SpreeIpay::Preferences.live_mode ? '1' : '0',
        SpreeIpay::Preferences.vendor_id,
        transaction_id
      ].join

      Rails.logger.info "OMKUU Status check data string: #{data_string}"

      # Generate hash using HMAC SHA1
      hash = OpenSSL::HMAC.hexdigest('sha1', SpreeIpay::Preferences.secret_key, data_string)
      
      Rails.logger.info "OMKUU Generated status hash: #{hash}"
      hash
    end

    def generate_cancel_hash(transaction_id)
      # Generate hash for cancellation
      data_string = [
        SpreeIpay::Preferences.live_mode ? '1' : '0',
        SpreeIpay::Preferences.vendor_id,
        transaction_id
      ].join

      Rails.logger.info "OMKUU Cancellation data string: #{data_string}"

      # Generate hash using HMAC SHA1
      hash = OpenSSL::HMAC.hexdigest('sha1', SpreeIpay::Preferences.secret_key, data_string)
      
      Rails.logger.info "OMKUU Generated cancel hash: #{hash}"
      hash
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
      Rails.logger.info "OMKUU [IPay#source_required?] Checking if source is required - returning true"
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
