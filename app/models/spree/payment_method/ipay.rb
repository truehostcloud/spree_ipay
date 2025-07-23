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
                                              "#{Rails.application.routes.url_helpers.root_url.chomp('/')}/ipay/confirm"
                                            }

    # Payment channels (in display order)
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

    # Ensure preferences are sorted in the desired display order
    def self.preference_order
      [
        :vendor_id, :hash_key, :test_mode, :currency,
        :callback_url, :return_url,
        :mpesa, :bonga, :airtel, :equity, :mobilebanking, :creditcard, :unionpay,
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
            bonga: preferred_bonga,
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

    # Channel preferences (duplicates removed)
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
  log_prefix = '[IPAY_HASH_DEBUG]'
  
  begin
    Rails.logger.info "#{log_prefix} ===== START HASH GENERATION ====="
    
    # Get values from payment method preferences
    vendor_id = preferred_vendor_id.to_s
    hash_key = preferred_hash_key.to_s
    
    # Log basic info
    Rails.logger.info "#{log_prefix} Order: #{payment.order.number}"
    Rails.logger.info "#{log_prefix} Vendor ID: #{vendor_id}"
    Rails.logger.info "#{log_prefix} Test Mode: #{test_mode?}"
    
    # Validate required preferences
    if vendor_id.blank? || hash_key.blank?
      error_msg = "Missing required iPay credentials - Vendor ID: #{vendor_id.present? ? 'present' : 'missing'}, Hash Key: #{hash_key.present? ? 'present' : 'missing'}"
      Rails.logger.error "#{log_prefix} #{error_msg}"
      raise error_msg
    end
    
    # Set live mode (0 for test, 1 for live)
    live = test_mode? ? "0" : "1"
    
    # Get values from payment and order
    oid = payment.order.number
    inv = "#{payment.order.number}#{Time.now.to_i}" # unique invoice
    ttl = payment.amount.ceil.to_s # Round up to nearest integer
    tel = phone || payment.order.bill_address&.phone || ''
    eml = payment.order.email
    vid = vendor_id
    curr = preferred_currency.presence || 'KES'
    p1 = ""
    p2 = ""
    p3 = ""
    p4 = ""
    cbk = preferred_callback_url.presence || "https://#{base_url}/ipay/confirm"
    cst = "1"
    crl = "2"
    
    # Log all values that will be used in the hash
    Rails.logger.info "#{log_prefix} Hash Input Values:"
    Rails.logger.info "#{log_prefix}   - live: #{live}"
    Rails.logger.info "#{log_prefix}   - oid: #{oid}"
    Rails.logger.info "#{log_prefix}   - inv: #{inv}"
    Rails.logger.info "#{log_prefix}   - ttl: #{ttl}"
    Rails.logger.info "#{log_prefix}   - tel: #{tel}"
    Rails.logger.info "#{log_prefix}   - eml: #{eml}"
    Rails.logger.info "#{log_prefix}   - vid: #{vid}"
    Rails.logger.info "#{log_prefix}   - curr: #{curr}"
    Rails.logger.info "#{log_prefix}   - cbk: #{cbk}"
    Rails.logger.info "#{log_prefix}   - cst: #{cst}"
    Rails.logger.info "#{log_prefix}   - crl: #{crl}"
    
    # Create datastring in the exact order required by iPay
    datastring = [
      live, oid, inv, ttl, tel, eml, vid, curr,
      p1, p2, p3, p4, cbk, cst, crl
    ].join
    
    Rails.logger.info "#{log_prefix} Datastring before hashing: #{datastring}"
    Rails.logger.info "#{log_prefix} Hash key (first 4 chars): #{hash_key[0..3]}..."
    
    # Generate hash using OpenSSL to match PHP's hash_hmac('sha1', ...)
    digest = OpenSSL::Digest.new('sha1')
    hmac = OpenSSL::HMAC.hexdigest(digest, hash_key, datastring)
    
    Rails.logger.info "#{log_prefix} Generated HMAC: #{hmac}"
    Rails.logger.info "#{log_prefix} ===== END HASH GENERATION ====="
    
    hmac
  rescue StandardError => e
    Rails.logger.error "#{log_prefix} Error in ipay_signature_hash: #{e.class} - #{e.message}"
    Rails.logger.error "#{log_prefix} Backtrace:\n#{e.backtrace.join("\n")}"
    raise "Error generating hash: #{e.message}"
  end
end

    def generate_ipay_form_html(payment, phone = nil)
      # Get values from payment method preferences
      live = preferred_test_mode ? '0' : '1'
      oid = payment.order.number.to_s
      inv = "#{payment.order.number}#{Time.now.to_i}" # unique invoice
      ttl = (payment.amount.to_f * 100).to_i.to_s # Convert to cents
      tel = phone.presence || payment.order.bill_address&.phone.to_s.presence || "0700000000"
      eml = payment.order.email.to_s
      vid = preferred_vendor_id.to_s.downcase
      curr = preferred_currency.presence || 'KES'
      p1 = ""
      p2 = ""
      p3 = ""
      p4 = ""
      
      # Use the base URL for fallback URLs
      default_url = "https://#{base_url}"
      
      # Set callback and return URLs
      cbk = preferred_callback_url.presence || "#{default_url}/ipay/confirm"
      lbk = preferred_return_url.presence || cbk
      
      # Log URLs for debugging
      Rails.logger.info("[iPay FORM DEBUG] Using callback URL (cbk): #{cbk}")
      Rails.logger.info("[iPay FORM DEBUG] Using return URL (lbk): #{lbk}")
      
      # Generate the hash with the phone number
      hsh = ipay_signature_hash(payment, tel)
      
      # Prepare iPay parameters - must match the exact order and parameters used in hash generation
      ipay_params = {
        'live' => live,
        'oid' => oid,
        'inv' => inv,
        'ttl' => ttl,
        'tel' => tel,
        'eml' => eml,
        'vid' => vid,
        'curr' => curr,
        'p1' => p1,
        'p2' => p2,
        'p3' => p3,
        'p4' => p4,
        'cbk' => cbk,
        'lbk' => lbk,
        'cst' => '1',  # Customer email notification flag
        'crl' => '2',  # Customer phone notification flag
        'hsh' => hsh
      }
      
      # Log the parameters being sent to iPay
      Rails.logger.info("[iPay FORM DEBUG] ipay_params: #{ipay_params.to_json}")
      
      # Add channel parameters based on preferences
      %w[mpesa bonga airtel equity mobilebanking creditcard unionpay mvisa vooma pesalink autopay].each do |channel|
        preference_method = "preferred_#{channel}"
        is_enabled = if respond_to?(preference_method)
                      send(preference_method)
                    else
                      # Fallback to default (mpesa enabled, others disabled)
                      channel == 'mpesa'
                    end
        ipay_params[channel] = is_enabled ? '1' : '0'
      end
      
      # Generate the form HTML with full-page flexible layout and improved button positioning
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Redirecting to iPay</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <style>
            @keyframes spin {
              to { transform: rotate(360deg); }
            }
            .animate-spin {
              animation: spin 1s linear infinite;
            }
          </style>
        </head>
        <body class="bg-gradient-to-br from-blue-100 to-gray-100 flex items-center justify-center min-h-screen w-full p-4 sm:p-6">
          <div class="bg-white rounded-xl shadow-xl w-full max-w-3xl mx-auto p-6 sm:p-8 flex flex-col justify-center space-y-6">
            <div class="flex justify-center">
              <svg class="animate-spin h-14 w-14 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
            </div>
            <h2 class="text-3xl sm:text-4xl font-extrabold text-gray-800 text-center">Redirecting to iPay</h2>
            <p class="text-gray-600 text-lg sm:text-xl text-center">Please wait while we securely redirect you to the payment page.</p>
            <p class="text-sm sm:text-base text-gray-500 text-center">If you are not redirected automatically, please click the button below.</p>
            <form id="ipay-payment-form" action="https://sandbox.ipayafrica.com/v3/ke" method="post" class="flex justify-center">
              #{ipay_params.map { |k, v| "<input type='hidden' name='#{k}' value='#{ERB::Util.html_escape(v)}'>" }.join("\n")}
              <button type="submit" class="bg-blue-600 text-white font-semibold py-2 px-4 rounded-md hover:bg-blue-700 transition duration-300">Proceed to Payment</button>
            </form>
            <script>
              document.addEventListener('DOMContentLoaded', function() {
                setTimeout(function() {
                  document.getElementById('ipay-payment-form').submit();
                }, 1000);
              });
            </script>
          </div>
        </body>
        </html>
      HTML
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

      # Add channel parameters in the correct order
      %w[mpesa bonga airtel equity mobilebanking creditcard unionpay mvisa vooma pesalink autopay].each do |channel|
        # Use the proper preference accessor method
        preference_method = "preferred_#{channel}"
        if respond_to?(preference_method)
          params[channel] = send(preference_method) ? '1' : '0'
        end
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
      # Prepare all values - must match exactly what will be sent in the form
      live = preferred_test_mode ? '0' : '1'
      oid = payment.order.number
      inv = payment.order.number
      ttl = (payment.amount.to_f * 100).to_i.to_s # Amount in cents
      tel = '' # Empty as per iPay docs when not used
      eml = payment.order.email
      vid = preferred_vendor_id.to_s.downcase
      curr = preferred_currency.presence || 'KES'
      p1 = ''
      p2 = ''
      p3 = ''
      p4 = ''
      cbk = preferred_callback_url.presence || "https://#{base_url}/ipay/confirm"
      lbk = preferred_return_url.presence || cbk
      cst = '1'
      crl = '2'

      # Create data string in the exact order required by iPay
      data_string = [
        live,   # live
        oid,    # order ID
        inv,    # invoice number
        ttl,    # total amount (in cents)
        tel,    # tel (empty as per iPay docs)
        eml,    # email
        vid,    # vendor ID (must be lowercase)
        curr,   # currency
        p1,     # p1
        p2,     # p2
        p3,     # p3
        p4,     # p4
        cbk,    # callback URL
        lbk,    # return URL
        cst,    # cst
        crl     # crl
      ].join

      # Generate and return hash using HMAC SHA1
      OpenSSL::HMAC.hexdigest('sha1', preferred_hash_key, data_string).downcase
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
