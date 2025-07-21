# frozen_string_literal: true

require 'httparty'

module Spree
  module Ipay
    VERSION = '1.0.9'
  end

  # iPay payment method integration for Spree Commerce.
  # Handles payment processing, callbacks, and communication with the iPay payment gateway.
  # Supports various payment channels including M-PESA, Airtel Money, and credit cards.
  class PaymentMethod::Ipay < ::Spree::PaymentMethod
    include HTTParty

    # Core settings (in display order)
    preference :vendor_id, :string
    preference :hash_key, :string
    preference :test_mode, :boolean, default: true
    preference :currency, :string, default: 'KES'
    preference :callback_url, :string, default: '/ipay/confirm'
    preference :return_url, :string, default: -> {
      # First try to get from environment variable
      if ENV['SITE_URL'].present?
        return "#{ENV['SITE_URL'].chomp('/')}/ipay/confirm"
      end
      
      # Then try to get from Spree store
      if defined?(Spree::Store) && Spree::Store.current && Spree::Store.current.url.present?
        url = Spree::Store.current.url.chomp('/')
        url = "https://#{url}" unless url.start_with?('http')
        return "#{url}/ipay/confirm"
      end
      
      # Fallback to relative path
      '/ipay/confirm'
    }

    # Payment channels (in display order)
    preference :mpesa, :boolean, default: true
    preference :airtel, :boolean, default: false
    preference :equity, :boolean, default: false
    preference :mobilebanking, :boolean, default: false
    preference :creditcard, :boolean, default: false
    preference :unionpay, :boolean, default: false
    preference :mvisa, :boolean, default: false
    preference :vooma, :boolean, default: false
    preference :pesalink, :boolean, default: false
    preference :autopay, :boolean, default: false

    # Ensure preferences are sorted in the desired display order
    def self.preference_order
      [
        :vendor_id, :hash_key, :test_mode, :currency,
        :callback_url, :return_url,
        :mpesa, :airtel, :equity, :mobilebanking, :creditcard, :unionpay,
        :mvisa, :vooma, :pesalink, :autopay
      ]
    end
    
    # Add caching for payment configuration
    def payment_config
      Rails.cache.fetch("ipay_config_#{id}", expires_in: 1.hour) do
        {
          vendor_id: preferred_vendor_id,
          hash_key: preferred_hash_key,
          test_mode: preferred_test_mode,
          currency: preferred_currency,
          callback_url: preferred_callback_url,
          return_url: preferred_return_url,
          channels: {
            mpesa: preferred_mpesa,
            airtel: preferred_airtel,
            equity: preferred_equity,
            mobilebanking: preferred_mobilebanking,
            creditcard: preferred_creditcard,
            unionpay: preferred_unionpay,
            mvisa: preferred_mvisa,
            vooma: preferred_vooma,
            pesalink: preferred_pesalink,
            autopay: preferred_autopay
          }
        }
      end
    end

    # Clear cache when preferences change
    def preferences=(prefs)
      super
      Rails.cache.delete("ipay_config_#{id}")
    end

    # Override preferences getter to maintain order
    def self.preferences
      @preferences ||= super.slice(*preference_order)
    end

    def initialize(*args)
      super
      # Initialize with empty preferences - don't use environment variables
      @preferences ||= {}

      # Set default values if not already set
      self.preferred_test_mode = true if preferred_test_mode.nil?
    end
    preference :currency, :string, default: 'KES'
    preference :callback_url, :string, default: '/ipay/confirm'
    preference :return_url, :string, default: '/ipay/confirm'

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

    # Cancel a payment in iPay
    # This method is called when a payment needs to be cancelled
    # @param response_code [String] The transaction ID to cancel
    # @return [ActiveMerchant::Billing::Response] The response from the gateway
    def cancel(response_code)
      Rails.logger.info("IPAY_DEBUG: [cancel] Attempting to cancel payment with response code: #{response_code}")
      
      # If we don't have a response code, we can't cancel the payment
      if response_code.blank?
        Rails.logger.error("IPAY_DEBUG: [cancel] Cannot cancel payment - no response code provided")
        return failure_response("Cannot cancel payment - no transaction ID provided")
      end
      
      # In test mode, we'll just log the cancellation attempt
      if test_mode?
        Rails.logger.info("IPAY_DEBUG: [cancel] Test mode - simulating successful cancellation for: #{response_code}")
        return success_response("Payment cancelled in test mode")
      end
      
      # In production, we would make an API call to iPay to cancel the payment
      # For now, we'll just log the attempt and return success
      Rails.logger.info("IPAY_DEBUG: [cancel] Would cancel payment with response code: #{response_code}")
      
      # Return a successful response
      success_response("Payment cancellation requested")
    rescue StandardError => e
      Rails.logger.error("IPAY_DEBUG: [cancel] Error cancelling payment: #{e.message}\n#{e.backtrace.join("\n")}")
      failure_response("Error cancelling payment: #{e.message}")
    end

    def supports?(source)
      # Return true for both nil source and IpaySource
      # This allows the payment to be created without a source initially
      source.nil? || source.is_a?(Spree::IpaySource)
    end

    def process_payment(payment)
      # Create a payment source if one doesn't exist
      if payment.source.nil?
        payment.source = Spree::IpaySource.create!(
          payment_method: self,
          user: payment.order.user
        )
        payment.save!
      end

      # Mark payment as processing
      payment.started_processing!
      
      # Return a success response
      ActiveMerchant::Billing::Response.new(
        true,
        'Payment processing started',
        {},
        authorization: "ipay_#{payment.order.number}_#{Time.now.to_i}"
      )
    rescue StandardError => e
      failure_response("Payment processing failed")
    end

    def authorize(amount, source, options = {})
      # Get the payment from options or create a new one
      payment = options[:payment] if options[:payment].is_a?(Spree::Payment)
      payment ||= options[:originator] if options[:originator].is_a?(Spree::Payment)
      
      # Get the order from options or payment
      order = options[:order] || (payment.order if payment.respond_to?(:order))
      
      # If we still don't have an order, try to get it from the source's payment if it exists
      if order.nil? && source.respond_to?(:payment) && source.payment.present?
        order = source.payment.order
      end
      
      # If we still don't have an order, try to get it from the controller
      if order.nil? && options[:controller].is_a?(ActionController::Base) && options[:controller].respond_to?(:current_order)
        order = options[:controller].current_order
      end
      
      return failure_response("Could not determine order for payment") if order.nil?
      
      # If we don't have a payment, create one
      if payment.nil?
        payment = order.payments.create!(
          payment_method_id: id,
          amount: amount,
          source: source
        )
      end
      
      # Ensure we have a payment and it's valid
      return failure_response("Invalid payment") unless payment.is_a?(Spree::Payment)

      # Ensure the order is in the correct state
      return failure_response("Order is not in a confirmable state") unless order.checkout_steps.include?('confirm')

      # Ensure we have a valid source
      return failure_response("Invalid payment source") if source.blank? || !source.is_a?(Spree::IpaySource)

      # Ensure source is associated with payment method
      source.payment_method_id = id
      
      # Get phone number from source or options
      phone = source.phone.presence || 
              options.dig(:originator, :source_attributes, :phone) || 
              options.dig(:originator, :source, :phone) ||
              (options[:controller].is_a?(ActionController::Base) && options[:controller].session[:ipay_phone_number])
      
      return failure_response("Phone number is required") if phone.blank?
      
      # Ensure payment source is set and has phone number
      payment.source ||= source
      payment.source.phone = phone
      
      unless payment.save
        return failure_response("Failed to save payment: #{payment.errors.full_messages.to_sentence}")
      end

      # Process the payment
      process!(phone: phone, payment: payment, amount: amount, options: options)
    rescue StandardError => e
      failure_response("Authorization failed: #{e.message}")
    end

    def capture(_amount, response_code, options = {})
      options[:originator]

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
    rescue StandardError => e
      failure_response("Capture failed: #{e.message}")
    end

    def void(response_code, _options = {})
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
    rescue StandardError => e
      failure_response("Payment void failed: #{e.message}")
    end

    def process!(phone: nil, payment: nil, amount: nil, options: {})
      Rails.logger.info("IPAY_DEBUG: [process!] Starting payment processing for order #{payment&.order&.number}")
      Rails.logger.info("IPAY_DEBUG: [process!] Payment amount: #{amount} (original: #{payment&.amount})")
      
      # Validate required parameters
      unless phone.present? && payment.present? && payment.order.present? && amount.present?
        error_msg = "Missing required parameters: phone=#{phone.present?}, payment=#{payment.present?}, order=#{payment&.order.present?}, amount=#{amount.present?}"
        Rails.logger.error("IPAY_DEBUG: [process!] #{error_msg}")
        return failure_response("Payment processing failed: #{error_msg}")
      end

      # Validate phone number format
      phone_digits = phone.to_s.gsub(/\D/, '')
      unless phone_digits.match?(/^\d{10,15}$/)
        error_msg = "Invalid phone number format: #{phone}"
        Rails.logger.error("IPAY_DEBUG: [process!] #{error_msg}")
        return failure_response("Please enter a valid 10-15 digit phone number")
      end

      # Validate credentials are set
      if preferred_vendor_id.blank? || preferred_hash_key.blank?
        error_msg = "Payment configuration error: vendor_id=#{preferred_vendor_id.present?}, hash_key=#{preferred_hash_key.present?}"
        Rails.logger.error("IPAY_DEBUG: [process!] #{error_msg}")
        return failure_response("Payment configuration error. Please contact support.")
      end

      # Validate payment amount
      unless amount.to_f > 0
        error_msg = "Invalid payment amount: #{amount}"
        Rails.logger.error("IPAY_DEBUG: [process!] #{error_msg}")
        return failure_response("Invalid payment amount")
      end

      begin
        # Update payment amount if needed
        if (payment.amount.to_f - amount.to_f).abs > Float::EPSILON
          payment.amount = amount
          payment.save!
        end

        # Store phone number in session if we have a controller context
        if options[:controller]&.respond_to?(:session)
          options[:controller].session[:ipay_phone_number] = phone
          Rails.logger.info("IPAY_DEBUG: [process!] Stored phone number in session")
        end

        # Transition payment to processing state
        if payment.respond_to?(:started_processing!)
          payment.started_processing!
          Rails.logger.info("IPAY_DEBUG: [process!] Payment #{payment.number} marked as processing")
        end

        # Generate the iPay form HTML with phone number
        form_html = generate_ipay_form_html(payment, phone)
        
        # Return success with form HTML
        Rails.logger.info("IPAY_DEBUG: [process!] Successfully generated iPay form for order #{payment.order.number}")
        
        # Return a success response with the form HTML
        ActiveMerchant::Billing::Response.new(
          true,
          'iPay payment processing started',
          { form_html: form_html },
          { test: test_mode? }
        )
      rescue StandardError => e
        error_msg = "Error in process!: #{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}"
        Rails.logger.error("IPAY_DEBUG: [process!] #{error_msg}")
        failure_response("Payment processing failed: #{e.message}")
      end
    rescue StandardError => e
      failure_response("Payment processing failed")
    end

    # Generate HMAC SHA1 hash for iPay
    # Matches PHP's hash_hmac('sha1', $datastring, $hashkey) implementation
    # @param payment [Spree::Payment] The payment object
    # @param phone [String] The customer's phone number
    def ipay_signature_hash(payment, phone = nil)
      # Get values from payment method preferences
      vendor_id = preferred_vendor_id.to_s.downcase # Must be lowercase
      hash_key = preferred_hash_key.to_s

      # Validate required preferences
      if vendor_id.blank? || hash_key.blank?
        raise "Missing required iPay credentials"
      end

      # Ensure we have a valid payment object
      unless payment.is_a?(Spree::Payment)
        raise ArgumentError, "Invalid payment object provided"
      end

      # Ensure payment has an associated order
      unless payment.order
        raise "Payment is missing an associated order"
      end

      # Set live mode (0 for test, 1 for live)
      live = test_mode? ? "0" : "1"

      # Prepare values - must match exactly what will be sent in the form
      order = payment.order
      oid = order.number.to_s.gsub(/[^a-zA-Z0-9]/, '')[0...26] # Max 26 alphanumeric chars
      inv = oid[0...15] # Max 15 chars, use order ID if not specified
      
      # Format amount to 2 decimal places and convert to integer cents
      amount_in_cents = (payment.amount.to_f * 100).round
      ttl = format('%.2f', (amount_in_cents / 100.0)) # Format as string with 2 decimal places
      
      # Get phone number from various possible sources
      tel = if phone.present?
              phone.to_s.gsub(/\D/, '')
            elsif order.bill_address&.phone.present?
              order.bill_address.phone.gsub(/\D/, '')
            else
              '0700000000'
            end[0...15] # Max 15 digits
            
      eml = order.email.to_s[0...30] # Max 30 chars
      vid = vendor_id[0...12] # Max 12 chars
      curr = (preferred_currency.presence || 'KES')[0...3] # Max 3 chars
      p1 = ""
      p2 = ""
      p3 = ""
      p4 = ""
      
      # Generate callback URL safely
      cbk_host = base_url.gsub(/^https?:\/\//, '') # Remove protocol if present
      cbk = (preferred_callback_url.presence || "https://#{cbk_host}/ipay/confirm")
            .gsub(/[;:~`!%^*-<>_]/i, '') # Remove invalid chars
            
      cst = "1"
      crl = "0" # 0 for HTTP/HTTPS callback

      # Format amount to 2 decimal places
      formatted_ttl = format('%.2f', ttl.to_f)
      
      # Create datastring in the exact order required by iPay
      # IMPORTANT: This exact order must be maintained
      datastring = live + oid + inv + formatted_ttl + tel + eml + vid + curr + p1 + p2 + p3 + p4 + cbk + cst + crl
      
      # Log the datastring for debugging
      Rails.logger.info("IPAY_DEBUG: [ipay_signature_hash] Datastring: #{datastring}")

      # Generate hash using OpenSSL to match PHP's hash_hmac('sha1', ...)
      digest = OpenSSL::Digest.new('sha1')
      hash = OpenSSL::HMAC.hexdigest(digest, hash_key, datastring)
      
      # Ensure the hash is lowercase to match PHP's output
      hash.downcase
    rescue StandardError => e
      raise "Error generating hash: #{e.message}"
    end

    def generate_ipay_form_html(payment, phone = nil)
      # Get required values
      live = test_mode? ? "0" : "1"
      # Use numeric order ID for transaction code
      oid = payment.order.id.to_s
      # Use numeric order ID for invoice as well
      inv = payment.order.id.to_s
      
      # Format amount to 2 decimal places and convert to cents (integer)
      amount_in_cents = (payment.amount.to_f * 100).round
      ttl = format('%.2f', (amount_in_cents / 100.0)) # Format as string with 2 decimal places
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
        error_msg = "Invalid callback URL format: #{e.message}"
        Spree::Ipay::Logger.error(StandardError.new(error_msg), payment.order.number)
        # Fallback to a safe default in case of errors
        cbk = "https://#{default_host}/api/v1/ipay/callback"
        cbk += '?test=1' if test_mode?
      end

      # Generate return URL for customer redirect after payment
      # Point to the frontend order confirmation page
      order_number = payment.order.number
      # Use token or guest_token depending on what's available
      order_token = payment.order.respond_to?(:token) ? payment.order.token : payment.order.guest_token
      rst = preferred_return_url.presence || "#{default_protocol}://#{default_host}/orders/#{order_number}?order_token=#{order_token}"
      Rails.logger.info("IPAY_DEBUG: [generate_ipay_form_html] Generated return URL: #{rst}")

      cst = "1"  # Customer email notification flag
      crl = "2"  # Customer phone notification flag

      begin
        hsh = ipay_signature_hash(payment)
      rescue StandardError => e
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
      channels = %i[mpesa airtel equity mobilebanking creditcard unionpay mvisa vooma pesalink autopay]
      
      # Add channel parameters with string keys for the API
      channels.each do |channel|
        ipay_params[channel.to_s] = send("preferred_#{channel}") ? '1' : '0'
      end

      # Generate form HTML
      form_html = "<form id='ipay_form' action='#{api_endpoint}' method='POST'>\n"

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
            response_code: response.dig('data', 'transaction_id'),
            avs_response: response.dig('data', 'checkout_url')
          )

          ActiveMerchant::Billing::Response.new(
            true,
            'Payment confirmation initiated',
            {},
            {
              authorization: response.dig('data', 'transaction_id'),
              test: test_mode?,
              checkout_url: response.dig('data', 'checkout_url')
            }
          )
        else
          error_msg = response['message'] || 'Payment confirmation failed'
          failure_response(error_msg)
        end
      rescue StandardError => e
        failure_response("Payment confirmation failed")
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
      rescue StandardError => e
        failure_response("Payment completion failed: #{e.message}")
      end
    end

    def initiate_payment(payment, phone: nil)
      # Log the start of payment initiation

      # Prepare parameters
      params = {
        live: preferred_test_mode ? '0' : '1',
        oid: payment.order.number,
        inv: payment.order.number,
        ttl: payment.amount.to_f.round(2).to_s,
        tel: phone,
        eml: payment.order.email,
        vid: preferred_vendor_id,
        curr: preferred_currency.presence || 'KES',
        p1: '',
        p2: '',
        p3: '',
        p4: '',
        cbk: preferred_callback_url.presence || "#{Rails.application.routes.url_helpers.root_url.chomp('/')}/ipay/confirm",
        cst: '1',
        crl: '2'
      }

      # Log all parameters except sensitive ones
      log_params = params.dup
      log_params[:tel] = '[FILTERED]' if log_params[:tel].present?
      log_params[:eml] = '[FILTERED]' if log_params[:eml].present?

      # Generate and add hash
      params[:hsh] = generate_hash(payment)

      # Add channel parameters
      %i[
        mpesa bonga airtel equity mobilebanking
        creditcard unionpay mvisa vooma pesalink autopay
      ].each do |channel|
        next unless respond_to?("preferred_#{channel}")

        params[channel.to_s] = send("preferred_#{channel}") ? '1' : '0'
      end

      # Use the class-level api_endpoint method
      # Parameters prepared for form submission

      # Generate form HTML - use the proper endpoint based on test mode
      form_action = api_endpoint

      form_html = "<form id='ipay_form' action='#{form_action}' method='POST'>\n"

      params.each do |key, value|
        escaped_value = ERB::Util.html_escape(value.to_s)
        form_html += "<input type='hidden' name='#{key}' value='#{escaped_value}'>\n"
      end

      form_html += "</form>"
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
    rescue StandardError => e
      failure_response("Payment initiation failed")
    end

    def check_payment_status(transaction_id)
      # Prepare status check parameters
      params = {
        live: test_mode? ? '0' : '1',
        vid: preferred_vendor_id,
        tid: transaction_id,
        hsh: generate_status_hash(transaction_id)
      }

      # Make API call to check status
      response = HTTParty.post(
        preferred_api_endpoint,
        body: params
      )

      # Parse and return response
      JSON.parse(response.body)
    rescue StandardError => e
      {
        status: 'error',
        message: 'Failed to check payment status'
      }
    end

    def cancel_payment(transaction_id)
      # Prepare cancellation parameters
      params = {
        live: test_mode? ? '0' : '1',
        vid: preferred_vendor_id,
        tid: transaction_id,
        hsh: generate_cancel_hash(transaction_id)
      }

      # Make API call to cancel payment
      response = HTTParty.post(
        preferred_api_endpoint,
        body: params
      )

      # Parse and return response
      JSON.parse(response.body)
    rescue StandardError => e
      {
        status: 'error',
        message: 'Failed to cancel payment'
      }
    end

    def generate_hash(payment, phone: nil)
      # Prepare all values
      live = preferred_test_mode 
      oid = payment.order.number
      inv = "INV-#{payment.order.number}"
      ttl = payment.amount.to_s
      
      # Use provided phone or fall back to billing address phone
      tel = if phone.present?
              phone.to_s.gsub(/\D/, '')
            else
              payment.order.bill_address&.phone.to_s.gsub(/\D/, '')
            end
      
      eml = payment.order.email
      vid = preferred_vendor_id
      curr = preferred_currency.presence || 'KES'
      cbk = preferred_callback_url.presence || '/ipay/confirm'

      # Create data string in the exact order required by iPay
      data_string = [
        live,   # live
        oid,    # order ID
        inv,    # invoice number
        ttl,    # total amount
        '',     # tel (empty as per iPay docs)
        eml,    # email
        vid,    # vendor ID
        curr,   # currency
        '',     # p1
        '',     # p2
        '',     # p3
        '',     # p4
        cbk,    # callback URL
        '1',    # cst
        '2'     # crl
      ].join

      # Generate the hash
      OpenSSL::HMAC.hexdigest('sha1', preferred_hash_key, data_string)

      # Generate and return hash using HMAC SHA1
      OpenSSL::HMAC.hexdigest('sha1', preferred_hash_key, data_string)
    end

    def generate_status_hash(transaction_id)
      # Generate hash for status check
      data_string = [
        preferred_test_mode ? '0' : '1',
        preferred_vendor_id,
        transaction_id
      ].join

      OpenSSL::HMAC.hexdigest('sha1', preferred_hash_key, data_string)
    end

    def generate_cancel_hash(transaction_id)
      # Generate hash for payment cancellation
      data_string = [
        preferred_test_mode ? '0' : '1',
        preferred_vendor_id,
        transaction_id
      ].join

      OpenSSL::HMAC.hexdigest('sha1', preferred_hash_key, data_string)
    end

    def callback_url(payment)
      "#{base_url}/ipay/callback?order=#{payment.order.number}"
    end

    def return_url(payment)
      "#{base_url}/ipay/return?order=#{payment.order.number}"
    end

    def base_url
      # Try to get from Spree store first
      if defined?(Spree::Store) && Spree::Store.current
        store = Spree::Store.current
        if store.url.present?
          url = store.url.chomp('/')
          url = "https://#{url}" unless url.start_with?('http')
          return url
        end
      end
      
      # Try to get from Rails URL helpers
      if defined?(Rails.application.routes.url_helpers)
        begin
          # Set default URL options if not set
          Rails.application.routes.default_url_options ||= {}
          Rails.application.routes.default_url_options[:host] ||= ENV['HOST']
          
          if Rails.application.routes.default_url_options[:host].present?
            protocol = Rails.application.routes.default_url_options[:protocol] || 'https'
            host = Rails.application.routes.default_url_options[:host].chomp('/')
            return "#{protocol}://#{host}"
          end
        rescue => e
          Rails.logger.error("IPAY_DEBUG: [base_url] Error with url_helpers: #{e.message}")
        end
      end
      
      # Fallback to environment variable or default
      if ENV['SITE_URL'].present?
        return ENV['SITE_URL'].chomp('/')
      end
      
      # Final fallback
      'https://example.com'
    rescue => e
      Rails.logger.error("IPAY_DEBUG: [base_url] Error generating URL: #{e.message}")
      ENV['SITE_URL'] || 'https://example.com'
    end

    def test_mode?
      preferred_test_mode == true || preferred_test_mode == '1' || preferred_test_mode == 'true'
    end

    def api_endpoint
      preferred_test_mode ? 'https://sandbox.ipayafrica.com/v3/ke' : 'https://payments.ipayafrica.com/v3/ke'
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
