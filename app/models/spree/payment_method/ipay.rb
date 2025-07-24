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
    preference :test_mode, :boolean, default: false # Live mode is default
    preference :currency, :string, default: 'KES'
    preference :callback_url, :string, default: '/ipay/confirm'
    preference :return_url, :string, default: -> {
                                              "#{Rails.application.routes.url_helpers.root_url.chomp('/')}/ipay/confirm"
                                            }

    # Payment channels (in display order)
    preference :mpesa, :boolean, default: true
    preference :airtel, :boolean, default: true
    preference :equity, :boolean, default: true
    preference :creditcard, :boolean, default: true
    preference :pesalink, :boolean, default: true
    preference :mobilebanking, :boolean, default: false
    preference :unionpay, :boolean, default: false
    preference :mvisa, :boolean, default: false
    preference :vooma, :boolean, default: false
    preference :autopay, :boolean, default: false

    # Generate callback and return URLs for iPay
    def generate_ipay_urls(payment)
      order = payment.order
      
      # Extract host and protocol from the return URL preference
      default_host = 'example.com'
      default_protocol = 'https'
      
      begin
        if preferred_return_url.present?
          return_uri = URI.parse(preferred_return_url)
          default_host = return_uri.host if return_uri.host.present?
          default_protocol = return_uri.scheme if return_uri.scheme.present?
        end
      rescue URI::InvalidURIError => e
        Spree::Ipay::Logger.error(e, "Invalid return URL format: #{e.message}")
      end

      # Generate callback URL for iPay to send payment status
      begin
        callback_path = '/api/v1/ipay/callback'
        
        if preferred_callback_url.present?
          callback_uri = URI.parse(preferred_callback_url)
          callback_uri.scheme ||= default_protocol
          callback_uri.host ||= default_host
          callback_uri.path = callback_path if callback_uri.path.blank? || callback_uri.path == '/'
        else
          protocol = test_mode? ? 'https' : default_protocol
          callback_uri = URI.parse("#{protocol}://#{default_host}#{callback_path}")
        end

        # Add test parameter if in test mode
        if test_mode?
          params = URI.decode_www_form(callback_uri.query || '').to_h
          params['test'] = '1'
          callback_uri.query = URI.encode_www_form(params) if params.any?
        end

        cbk = callback_uri.to_s
      rescue URI::InvalidURIError => e
        error_msg = "Invalid callback URL format: #{e.message}"
        Spree::Ipay::Logger.error(StandardError.new(error_msg), order.number)
        # Fallback to a safe default in case of errors
        cbk = "#{default_protocol}://#{default_host}#{callback_path}"
        cbk += '?test=1' if test_mode?
      end

      # Generate return URL for customer redirect
      begin
        return_path = "/orders/#{order.number}"
        
        if preferred_return_url.present?
          return_uri = URI.parse(preferred_return_url)
          return_uri.scheme ||= default_protocol
          return_uri.host ||= default_host
          return_uri.path = return_path if return_uri.path.blank? || return_uri.path == '/'
        else
          protocol = test_mode? ? 'https' : default_protocol
          return_uri = URI.parse("#{protocol}://#{default_host}#{return_path}")
        end

        # Add order token for guest access if available
        params = URI.decode_www_form(return_uri.query || '').to_h
        
        # Safely get guest token - handle both Spree 3.x and 4.x
        guest_token = if order.respond_to?(:guest_token)
                       order.guest_token
                     elsif order.respond_to?(:token)
                       order.token
                     elsif order.respond_to?(:guest_token=) && order.instance_variable_defined?(:@guest_token)
                       order.instance_variable_get(:@guest_token)
                     else
                       SecureRandom.hex(10) # Generate a random token as fallback
                     end
        
        params[:token] = guest_token if guest_token.present?
        return_uri.query = URI.encode_www_form(params) if params.any?

        lbk = return_uri.to_s
      rescue URI::InvalidURIError => e
        error_msg = "Invalid return URL format: #{e.message}"
        Spree::Ipay::Logger.error(StandardError.new(error_msg), order.number)
        # Fallback to a safe default in case of errors
        lbk = "#{default_protocol}://#{default_host}#{return_path}?token=#{guest_token}"
      end

      {
        cbk: cbk,      # Callback URL for server-to-server notification
        rst: lbk,      # Return URL for customer redirect
        cst: '1',      # Enable callback (1 = yes, 0 = no)
        crl: '0',      # Disable automatic redirect (0 = no redirect, 1 = redirect)
        hsh: generate_hash(payment)  # Generate the HMAC signature
      }
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
      options[:originator]
      order = payment.order

      # Ensure the order is in the correct state
      return failure_response("Order is not in a confirmable state") unless order.checkout_steps.include?('confirm')

      # Ensure we have a valid source
      return failure_response("Invalid payment source") if source.blank? || !source.is_a?(Spree::IpaySource)

      # Ensure source is associated with payment method
      if source.payment_method_id != id && !source.update(payment_method_id: id)
        return failure_response("Failed to update payment source")
      end

      # Get phone from source
      phone = source.phone

      # Store phone number in session if we have a controller context
      options[:controller].session[:ipay_phone_number] = phone if options[:controller]&.respond_to?(:session)

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
        return failure_response("Failed to update payment source") if payment.source.changed? && !payment.source.save
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
      # Validate required parameters
      unless phone.present? && payment.present? && payment.order.present? && amount.present?
        return failure_response("Missing required parameters")
      end

      # Validate phone number format
      phone_digits = phone.to_s.gsub(/\D/, '')
      unless phone_digits.match?(/^\d{10}$/)
        return failure_response("Invalid phone number format")
      end

      # Validate credentials are set
      if preferred_vendor_id.blank? || preferred_hash_key.blank?
        return failure_response("Payment configuration error")
      end

      # Validate payment amount
      unless amount.to_f > 0
        return failure_response('Invalid payment amount')
      end

      # Update payment amount if needed
      if (payment.amount.to_f - amount.to_f).abs > Float::EPSILON
        payment.amount = amount
        payment.save!
      end

      # Store phone number in session if we have a controller context
      options[:controller].session[:ipay_phone_number] = phone if options[:controller]&.respond_to?(:session)

      # Transition payment to processing state
      payment.started_processing! if payment.respond_to?(:started_processing!)

      success_response('Payment processing started')
    rescue StandardError => e
      failure_response("Payment processing failed")
    end

    # Generate HMAC SHA1 hash for iPay
    # Matches PHP's hash_hmac('sha1', $datastring, $hashkey) implementation
    # @param payment [Spree::Payment] The payment object
    # @param phone [String] The customer's phone number
    def ipay_signature_hash(payment, phone = nil)
      # Get values from payment method preferences
      vendor_id = preferred_vendor_id.to_s.downcase
      hash_key = preferred_hash_key.to_s

      # Validate required preferences
      if vendor_id.blank? || hash_key.blank?
        raise "Missing required iPay credentials"
      end

      # Set live mode (0 for test, 1 for live)
      live = test_mode? ? "0" : "1"

      # Prepare values in the exact order required by iPay
      oid = payment.number.to_s  # Use payment number for consistency
      inv = "#{payment.order.number}-#{Time.now.to_i}" # Unique invoice number
      ttl = (payment.amount.to_f * 100).to_i.to_s # Amount in cents (no decimals)
      tel = phone.presence || payment.order.bill_address&.phone.to_s.presence || "0700000000"
      eml = payment.order.email.to_s
      vid = vendor_id
      curr = preferred_currency.presence || 'KES'
      
      # Custom parameters (same as in form generation)
      p1 = "order_#{payment.order.number}"  # Order reference
      p2 = payment.payment_method.id.to_s   # Payment method ID
      p3 = ""  # Additional custom parameter
      p4 = ""  # Additional custom parameter
      
      # Generate callback URL (must match exactly what's in the form)
      urls = generate_ipay_urls(payment)
      cbk = urls[:cbk]
      
      # Control flags
      cst = "1"  # Enable callback
      crl = "0"  # Disable automatic redirect

      # Create datastring in the exact order required by iPay
      # Note: The order of these parameters is critical for the hash to be valid
      datastring = [
        live,   # live
        oid,    # oid
        inv,    # inv
        ttl,    # ttl
        tel,    # tel
        eml,    # eml
        vid,    # vid
        curr,   # curr
        p1,     # p1
        p2,     # p2
        p3,     # p3
        p4,     # p4
        cbk,    # cbk
        cst,    # cst
        crl     # crl
      ].join

      # Log the datastring for debugging (without sensitive data)
      log_datastring = datastring.dup
      log_datastring.gsub!(/hsh=[^&]*/, 'hsh=[FILTERED]') if log_datastring.include?('hsh=')
      Rails.logger.info "[iPay] Datastring for hash: #{log_datastring}"

      # Generate HMAC SHA1 hash
      digest = OpenSSL::Digest.new('sha1')
      hash = OpenSSL::HMAC.hexdigest(digest, hash_key, datastring)
      
      # Log the generated hash (first 8 chars for security)
      Rails.logger.info "[iPay] Generated hash: #{hash[0..7]}..."
      
      # Return the hash in lowercase to match PHP's output
      hash.downcase
    rescue StandardError => e
      error_msg = "Error generating iPay hash: #{e.message}"
      Rails.logger.error("[iPay] #{error_msg}")
      Rails.logger.error("[iPay] Backtrace: #{e.backtrace.join("\n")}")
      raise error_msg
    end

    def generate_ipay_form_html(payment)
      # Get required values
      live = test_mode? ? "0" : "1"
      
      # Use payment number for transaction code
      oid = payment.number.to_s
      # Generate a unique invoice number
      inv = "#{payment.order.number}-#{Time.now.to_i}"
      
      # Amount in cents (no decimals)
      ttl = (payment.amount.to_f * 100).to_i.to_s
      
      # Get customer contact info
      tel = payment.order.bill_address&.phone || "0700000000"
      eml = payment.order.email
      
      # Get merchant info
      vid = preferred_vendor_id
      curr = preferred_currency.presence || 'KES'
      
      # Custom parameters (can be used for tracking)
      p1 = "order_#{payment.order.number}"  # Order reference
      p2 = payment.payment_method.id.to_s   # Payment method ID
      p3 = ""  # Additional custom parameter
      p4 = ""  # Additional custom parameter
      
      # Generate URLs and get required flags
      urls = generate_ipay_urls(payment)
      cbk = urls[:cbk]  # Callback URL
      lbk = urls[:rst]  # Return URL
      
      # Set flags
      cst = "1"  # Enable callback
      crl = "0"  # Disable automatic redirect (let our callback handle it)
      
      # Generate the HMAC signature
      begin
        hsh = ipay_signature_hash(payment, tel)
      rescue StandardError => e
        Rails.logger.error("[iPay] Error generating payment hash: #{e.message}")
        raise "Error generating payment hash: #{e.message}"
      end

      # Prepare all iPay parameters with proper data types and consistent string values
      ipay_params = ActiveSupport::OrderedHash.new.tap do |params|
        # Required parameters
        params['live'] = live.to_s
        params['oid'] = oid.to_s
        params['inv'] = inv.to_s
        params['ttl'] = ttl.to_s
        params['tel'] = tel.to_s
        params['eml'] = eml.to_s
        params['vid'] = vid.to_s
        params['curr'] = curr.to_s
        
        # Custom parameters (p1-p4)
        params['p1'] = p1.to_s
        params['p2'] = p2.to_s
        params['p3'] = p3.to_s
        params['p4'] = p4.to_s
        
        # URL parameters
        params['cbk'] = cbk.to_s
        params['lbk'] = lbk.to_s
        
        # Control flags
        params['cst'] = cst.to_s
        params['crl'] = crl.to_s
        
        # Security
        params['hsh'] = hsh.to_s
        
        # Payment channels (must be in this specific order for hash generation)
        %w[mpesa airtel equity mobilebanking creditcard unionpay mvisa vooma pesalink autopay].each do |channel|
          params[channel] = send("preferred_#{channel}") ? '1' : '0'
        end
      end

      # Log the parameters being sent (without sensitive data)
      log_params = ipay_params.dup
      log_params['hsh'] = '[FILTERED]' if log_params['hsh']
      Rails.logger.info "[iPay] Generated form with params: #{log_params.inspect}"

      # Generate form HTML with proper encoding and security
      form_id = "ipay_form_#{SecureRandom.hex(4)}"
      form_html = ""
      
      # Add form with proper attributes
      form_html << "<form id='#{form_id}' action='#{ERB::Util.html_escape(api_endpoint)}' method='POST' accept-charset='UTF-8'>\n"
      
      # Add all parameters with proper escaping
      ipay_params.each do |key, value|
        form_html << "  <input type='hidden' name='#{ERB::Util.html_escape(key)}' value='#{ERB::Util.html_escape(value.to_s)}'>\n"
      end
      
      # Add submit button with fallback
      form_html << "  <div class='ipay-button-container'>\n"
      form_html << "    <button type='submit' class='ipay-button'>Complete Payment</button>\n"
      form_html << "  </div>\n"
      form_html << "</form>\n"
      
      # Add auto-submit script with error handling
      form_html << <<~HTML
        <script type='text/javascript'>
          document.addEventListener('DOMContentLoaded', function() {
            var form = document.getElementById('#{form_id}');
            if (form) {
              try {
                form.submit();
              } catch (e) {
                console.error('Error submitting iPay form:', e);
                // Show the submit button if auto-submit fails
                var button = form.querySelector('.ipay-button');
                if (button) button.style.display = 'block';
              }
            }
          });
        </script>
        <style>
          .ipay-button-container { margin: 20px 0; text-align: center; }
          .ipay-button { 
            padding: 12px 24px; 
            background-color: #4CAF50; 
            color: white; 
            border: none; 
            border-radius: 4px; 
            cursor: pointer; 
            font-size: 16px;
          }
          .ipay-button:hover { background-color: #45a049; }
        </style>
      HTML
      
      form_html.html_safe
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
      Rails.logger.info "[iPay] Starting payment initiation for order: #{payment.order.number}"

      # Prepare parameters
      params = {
        live: preferred_test_mode ? '0' : '1',
        oid: payment.order.number,
        inv: payment.order.number,
        ttl: payment.amount.to_i.to_s,
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

    def generate_hash(payment)
      # Prepare all values
      live = preferred_test_mode ? '0' : '1'
      oid = payment.order.number
      inv = payment.order.number
      ttl = payment.amount.to_i.to_s
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
      Rails.application.routes.url_helpers.root_url.chomp('/')
    end

    def test_mode?
      preferred_test_mode == true || preferred_test_mode == '1' || preferred_test_mode == 'true'
    end

    def api_endpoint
      endpoint = 'https://payments.ipayafrica.com/v3/ke' # Always use live endpoint
      Rails.logger.info("[iPay] Using API endpoint: #{endpoint}")
      endpoint
    end

    def success_response(message = 'Success')
      Rails.logger.info("[iPay] Success response: #{message}")
      ActiveMerchant::Billing::Response.new(
        true,
        message,
        {},
        test: test_mode?
      )
    end

    def failure_response(message = 'Failed')
      Rails.logger.error("[iPay] Failure response: #{message}")
      ActiveMerchant::Billing::Response.new(
        false,
        message,
        {},
        test: test_mode?
      )
    end
  end
end
