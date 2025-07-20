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

    def supports?(source)
      # Return true for both nil source and IpaySource
      # This allows the payment to be created without a source initially
      source.nil? || source.is_a?(Spree::IpaySource)
    end

    def process_payment(payment)
      # Log the start of payment processing
      Rails.logger.info("iPay#process_payment: Starting payment processing for payment ID: #{payment.id}")
      
      # Ensure we have a valid payment and order
      unless payment.is_a?(Spree::Payment)
        Rails.logger.error("iPay#process_payment: Invalid payment object provided")
        return failure_response("Invalid payment")
      end
      
      unless payment.order.present?
        Rails.logger.error("iPay#process_payment: No order found for payment ID: #{payment.id}")
        return failure_response("Order not found")
      end
      
      Rails.logger.info("iPay#process_payment: Processing payment for order ##{payment.order.number}")
      
      # Get phone number from params or session
      phone = nil
      
      # Try to get phone from source attributes if available
      if payment.source.is_a?(Spree::IpaySource) && payment.source.phone.present?
        phone = payment.source.phone
        Rails.logger.info("iPay#process_payment: Found phone in source: #{phone}")
      end
      
      # If no phone in source, try to get from order parameters
      if phone.blank? && payment.order.checkout_steps.include?('payment')
        Rails.logger.info("iPay#process_payment: Looking for phone in order params")
        params = payment.order.checkout_steps_params || {}
        Rails.logger.info("iPay#process_payment: Order params: #{params.inspect}")
        
        payment_attrs = params.dig(:order, :payments_attributes, 0) || {}
        Rails.logger.info("iPay#process_payment: Payment attributes: #{payment_attrs.inspect}")
        
        phone = payment_attrs.dig(:source_attributes, :phone)
        Rails.logger.info("iPay#process_payment: Found phone in params: #{phone}")
      end
      
      # Validate phone number
      phone_digits = phone.to_s.gsub(/\D/, '')
      Rails.logger.info("iPay#process_payment: Processed phone digits: #{phone_digits}")
      
      if phone_digits.blank? || (phone_digits.length != 10 && phone_digits.length != 12)
        error_msg = "A valid 10-digit phone number is required. Got: #{phone_digits}"
        Rails.logger.error("iPay#process_payment: #{error_msg}")
        return failure_response(error_msg)
      end
      
      # Convert to 254 format if needed
      if phone_digits.length == 10 && phone_digits.start_with?('0')
        original_phone = phone_digits.dup
        phone_digits = "254#{phone_digits[1..-1]}" 
        Rails.logger.info("iPay#process_payment: Converted phone number from #{original_phone} to #{phone_digits}")
      end
      
      # Create or update payment source
      if payment.source.nil? || !payment.source.is_a?(Spree::IpaySource)
        Rails.logger.info("iPay#process_payment: Creating new payment source")
        payment.source = Spree::IpaySource.create!(
          payment_method: self,
          user: payment.order.user,
          phone: phone_digits,
          status: 'pending'
        )
        Rails.logger.info("iPay#process_payment: Created payment source ID: #{payment.source.id}")
      else
        Rails.logger.info("iPay#process_payment: Updating existing payment source ID: #{payment.source.id}")
        payment.source.phone = phone_digits
        payment.source.status = 'pending' unless payment.source.status.present?
        payment.source.save!(validate: false)
        Rails.logger.info("iPay#process_payment: Updated payment source")
      end
      
      # Save the payment to ensure source is associated
      Rails.logger.info("iPay#process_payment: Saving payment")
      payment.save!
      Rails.logger.info("iPay#process_payment: Payment saved successfully")
      
      # Mark payment as processing
      begin
        Rails.logger.info("iPay#process_payment: Attempting to mark payment as processing")
        payment.started_processing!
        Rails.logger.info("iPay#process_payment: Payment marked as processing successfully. New state: #{payment.state}")
      rescue StandardError => e
        Rails.logger.error("iPay#process_payment: Failed to mark payment as processing: #{e.message}\n#{e.backtrace.join("\n")}")
        raise "Failed to process payment: #{e.message}"
      end
      
      # Log the payment processing
      Rails.logger.info("iPay#process_payment: Payment processing started for order #{payment.order.number}")
      
      # Return a success response
      ActiveMerchant::Billing::Response.new(
        true,
        'Payment processing started',
        {
          payment_id: payment.id,
          order_number: payment.order.number,
          amount: payment.amount.to_f,
          currency: payment.currency,
          phone: phone_digits
        },
        authorization: "ipay_#{payment.order.number}_#{Time.now.to_i}"
      )
    rescue StandardError => e
      Rails.logger.error("iPay payment processing failed: #{e.message}\n#{e.backtrace.join("\n")}")
      failure_response("Payment processing failed: #{e.message}")
    end

    def authorize(amount, source, options = {})
      Rails.logger.info("iPay#authorize: Starting authorization for amount: #{amount}")
      
      # Get the payment from options if available, otherwise use source
      payment = options[:payment] || (source.respond_to?(:payment) ? source.payment : nil)
      Rails.logger.debug("iPay#authorize: Payment from options/source: #{payment&.id}")
      
      # If we have an order number in options, try to find the payment that way
      if payment.nil? && options[:order_id].present?
        order_number = options[:order_id].to_s.split('-').first # Handle formats like 'R940832146-PLGSZU94'
        Rails.logger.debug("iPay#authorize: Looking up order by number: #{order_number}")
        order = Spree::Order.find_by(number: order_number)
        if order
          Rails.logger.debug("iPay#authorize: Found order #{order.number}, looking for payments with method_id: #{id}")
          payment = order.payments.where(payment_method_id: id).order(created_at: :desc).first
          Rails.logger.debug("iPay#authorize: Found payment from order: #{payment&.id}")
        end
      end
      
      # Try to get payment from source attributes
      if payment.nil? && source.respond_to?(:payment_id) && source.payment_id.present?
        Rails.logger.debug("iPay#authorize: Looking up payment by source.payment_id: #{source.payment_id}")
        payment = Spree::Payment.find_by(id: source.payment_id)
        Rails.logger.debug("iPay#authorize: Found payment by source.payment_id: #{payment&.id}")
      end
      
      # Try to get payment from order_id in source
      if payment.nil? && source.respond_to?(:order_id) && source.order_id.present?
        Rails.logger.debug("iPay#authorize: Looking up order by source.order_id: #{source.order_id}")
        order = Spree::Order.find_by(id: source.order_id)
        if order
          Rails.logger.debug("iPay#authorize: Found order #{order.number}, looking for payments with method_id: #{id}")
          payment = order.payments.where(payment_method_id: id).order(created_at: :desc).first
          Rails.logger.debug("iPay#authorize: Found payment from order: #{payment&.id}")
        end
      end
      
      # Try to get payment from originator
      if payment.nil? && options[:originator].is_a?(Spree::Payment)
        Rails.logger.debug("iPay#authorize: Using payment from originator: #{options[:originator].id}")
        payment = options[:originator]
      end
      
      # If we still don't have a payment, try to find it by the most recent payment for this source
      if payment.nil? && source.id.present?
        Rails.logger.debug("iPay#authorize: Looking for most recent payment with source_id: #{source.id}")
        payment = Spree::Payment.where(source_id: source.id, payment_method_id: id).order(created_at: :desc).first
        Rails.logger.debug("iPay#authorize: Found payment by source_id: #{payment&.id}")
      end
      
      # If we still don't have a payment, log all available information and fail
      if payment.nil?
        error_details = {
          source_type: source.class.name,
          source_attributes: source.attributes,
          options: options.except(:password, :card, :key, :login, :billing_address, :shipping_address),
          backtrace: caller(0, 5)  # Get the first 5 lines of the backtrace
        }
        
        Rails.logger.error("iPay#authorize: Could not determine payment for authorization. Details: #{error_details.to_json}")
        
        return failure_response(
          "Payment processing failed: Could not find payment record",
          code: 'payment_not_found',
          source_type: source.class.name,
          source_id: source.id,
          order_id: source.respond_to?(:order_id) ? source.order_id : nil,
          payment_method_id: id
        )
      end
      
      # Get the order and log its current state
      order = payment.order
      Rails.logger.info("iPay#authorize: Order #{order.number} is in state: #{order.state}")
      
      # Check if we can proceed with payment based on order state
      if order.completed?
        Rails.logger.info("iPay#authorize: Order is already completed")
      elsif order.confirm? || order.payment?
        Rails.logger.info("iPay#authorize: Order is in a valid state for payment")
      else
        # Try to advance the order state if possible
        begin
          Rails.logger.info("iPay#authorize: Attempting to advance order state from #{order.state}")
          
          # Get the current state index
          current_state_index = order.checkout_steps.index(order.state) || -1
          confirm_state_index = order.checkout_steps.index('confirm') || -1
          payment_state_index = order.checkout_steps.index('payment') || -1
          
          # If we're before the confirm or payment step, advance the order
          if current_state_index < [confirm_state_index, payment_state_index].max
            while order.next && order.state != 'confirm' && order.state != 'payment' && order.state != 'complete'
              Rails.logger.info("iPay#authorize: Advanced order to state: #{order.state}")
            end
          end
          
          # Reload the order to get the latest state
          order.reload
          Rails.logger.info("iPay#authorize: Order state after advancement: #{order.state}")
          
          # If we're still not in a valid state, return an error
          unless ['confirm', 'payment', 'complete'].include?(order.state)
            return failure_response(
              "Cannot process payment. Order is in state: #{order.state}",
              code: 'invalid_order_state',
              order_state: order.state,
              order_number: order.number,
              payment_id: payment.id,
              checkout_steps: order.checkout_steps
            )
          end
        rescue StandardError => e
          Rails.logger.error("iPay#authorize: Error advancing order state: #{e.message}")
          return failure_response(
            "Error preparing order for payment: #{e.message}",
            code: 'order_state_error',
            order_state: order.state,
            error: e.message
          )
        end
      end

      # Ensure we have a valid source
      return failure_response("Invalid payment source") if source.blank? || !source.is_a?(Spree::IpaySource)

      # Ensure source is associated with payment method
      if source.payment_method_id != id && !source.update(payment_method_id: id)
        return failure_response("Failed to update payment source")
      end

      # Get phone from source or options
      phone = source.phone || options[:phone]
      
      if phone.blank? && options[:controller]&.respond_to?(:session)
        phone = options[:controller].session[:ipay_phone_number]
      end
      
      return failure_response("Phone number is required") if phone.blank?

      # Update source with phone if needed
      # Update source phone if needed
      if source.phone.blank? && phone.present?
        source.phone = phone
        source.save(validate: false)
      end

      # Ensure payment has the source assigned
      if payment.source.nil? || !payment.source.is_a?(Spree::IpaySource)
        payment.source = source
        payment.payment_method_id = id

        # Save the payment to ensure source is associated
        unless payment.save
          return failure_response("Failed to save payment: #{payment.errors.full_messages.to_sentence}")
        end
      elsif payment.source.respond_to?(:phone) && payment.source.phone.blank? && phone.present?
        payment.source.phone = phone
        payment.source.save(validate: false)
      end

      order = payment.order
      phone = source.phone
      
      Rails.logger.info("iPay#authorize: Found payment #{payment.number} for order #{order.number}")
      Rails.logger.debug("iPay#authorize: Payment state: #{payment.state}, Amount: #{payment.amount}, Phone: #{phone}")
      
      begin
        # Process the payment
        Rails.logger.info("iPay#authorize: Processing payment with amount: #{amount}")
        result = process!(phone: phone, payment: payment, amount: amount, options: options)
        
        if result.success?
          Rails.logger.info("iPay#authorize: Payment processed successfully. Response: #{result.params}")
          # Update payment with response code if available
          if result.authorization.present?
            payment.update_columns(
              response_code: result.authorization,
              state: 'pending',
              updated_at: Time.current
            )
          end
        else
          Rails.logger.error("iPay#authorize: Payment processing failed: #{result.message}")
        end
        
        result
      rescue StandardError => e
        error_msg = "Unexpected error during payment processing: #{e.message}"
        Rails.logger.error("iPay#authorize: #{error_msg}\n#{e.backtrace.join("\n")}")
        failure_response("Payment processing failed: #{e.message}", code: 'processing_error')
      end
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
      # Log the start of payment processing
      Rails.logger.info("iPay#process!: Starting payment processing for payment ID: #{payment&.id}")
      Rails.logger.debug("iPay#process!: Phone: #{phone}, Amount: #{amount}, Options: #{options.inspect}")
      
      # Ensure we have all required parameters
      if phone.blank?
        error_msg = "Phone number is required"
        Rails.logger.error("iPay#process!: #{error_msg}")
        return failure_response(error_msg)
      end
      
      if payment.nil?
        error_msg = "Payment is required"
        Rails.logger.error("iPay#process!: #{error_msg}")
        return failure_response(error_msg)
      end
      
      if amount.nil?
        error_msg = "Amount is required"
        Rails.logger.error("iPay#process!: #{error_msg}")
        return failure_response(error_msg)
      end
      
      # Log payment state and source
      Rails.logger.info("iPay#process!: Payment state: #{payment.state}, Source: #{payment.source&.class&.name}")
      Rails.logger.debug("iPay#process!: Payment details - ID: #{payment.id}, Number: #{payment.number}, Amount: #{payment.amount}")

      # Ensure payment is in a processable state
      unless payment.pending? || payment.checkout?
        error_msg = "Payment is not in a processable state (current state: #{payment.state})"
        Rails.logger.error("iPay#process!: #{error_msg}")
        return failure_response(error_msg)
      end
      
      # Ensure phone is present and properly formatted
      phone = phone.to_s.strip
      phone_digits = phone.gsub(/\D/, '')
      
      Rails.logger.info("iPay#process!: Processing phone number: #{phone} (digits: #{phone_digits})")
      
      # Validate phone number format (10 or 12 digits)
      unless phone_digits.length == 10 || phone_digits.length == 12
        error_msg = "Phone number must be 10 digits (e.g., 0700123456) or 12 digits (e.g., 254700123456). Got: #{phone_digits}"
        Rails.logger.error("iPay#process!: #{error_msg}")
        return failure_response(error_msg)
      end
      
      # Convert to 254 format if needed
      if phone_digits.length == 10 && phone_digits.start_with?('0')
        original_phone = phone_digits.dup
        phone_digits = "254#{phone_digits[1..-1]}"
        Rails.logger.info("iPay#process!: Converted phone from #{original_phone} to #{phone_digits}")
      else
        Rails.logger.info("iPay#process!: Using phone as-is: #{phone_digits}")
      end
      
      # Ensure amount is valid and log the amount being processed
      amount = amount.to_f
      if amount <= 0
        Rails.logger.info("iPay#process!: Amount not provided or invalid, using payment amount")
        amount = payment.amount.to_f
        if amount <= 0
          error_msg = "Invalid payment amount: #{amount}. Amount must be greater than 0"
          Rails.logger.error("iPay#process!: #{error_msg}")
          return failure_response(error_msg)
        end
      end
      Rails.logger.info("iPay#process!: Processing payment amount: #{amount}")
      
      # Ensure payment method is properly configured
      if preferred_vendor_id.blank? || preferred_hash_key.blank?
        error_msg = "iPay configuration error: Missing vendor_id or hash_key"
        Rails.logger.error("iPay#process!: #{error_msg}")
        return failure_response("Payment configuration error. Please contact support.")
      end
      Rails.logger.debug("iPay#process!: Using vendor_id: #{preferred_vendor_id}")
      
      # Update payment state with detailed logging
      begin
        Rails.logger.info("iPay#process!: Attempting to start payment processing")
        if payment.can_start_processing?
          Rails.logger.info("iPay#process!: Payment can start processing, updating state")
          payment.started_processing!
          Rails.logger.info("iPay#process!: Payment state updated to: #{payment.state}")
        else
          Rails.logger.warn("iPay#process!: Payment cannot start processing. Current state: #{payment.state}")
        end
      rescue StandardError => e
        error_msg = "Failed to update payment state: #{e.message}"
        Rails.logger.error("iPay#process!: #{error_msg}\n#{e.backtrace.join("\n")}")
        return failure_response("Failed to initialize payment processing")
      end
      
      # Ensure payment source is properly set up
      if payment.source.nil? || !payment.source.is_a?(Spree::IpaySource)
        error_msg = "Invalid or missing payment source"
        Rails.logger.error("iPay#process!: #{error_msg}")
        return failure_response("Payment processing error. Please try again.")
      end
      
      # Update source with phone if needed
      if payment.source.phone.blank? || payment.source.phone != phone_digits
        Rails.logger.info("iPay#process!: Updating payment source phone from #{payment.source.phone} to #{phone_digits}")
        payment.source.phone = phone_digits
        payment.source.status = 'pending' unless payment.source.status.present?
        
        begin
          unless payment.source.save(validate: false)
            error_msg = "Failed to update payment source: #{payment.source.errors.full_messages.to_sentence}"
            Rails.logger.error("iPay#process!: #{error_msg}")
            return failure_response("Failed to update payment details")
          end
          Rails.logger.info("iPay#process!: Successfully updated payment source")
        rescue StandardError => e
          error_msg = "Error saving payment source: #{e.message}"
          Rails.logger.error("iPay#process!: #{error_msg}\n#{e.backtrace.join("\n")}")
          return failure_response("Payment processing error. Please try again.")
        end
      else
        Rails.logger.info("iPay#process!: Using existing payment source with phone: #{phone_digits}")
      end

      # Update payment amount if needed
      amount_diff = (payment.amount.to_f - amount).abs
      if amount_diff > Float::EPSILON
        Rails.logger.info("iPay#process!: Updating payment amount from #{payment.amount} to #{amount}")
        payment.amount = amount
        begin
          payment.save!
          Rails.logger.info("iPay#process!: Successfully updated payment amount to #{payment.amount}")
        rescue StandardError => e
          error_msg = "Failed to update payment amount: #{e.message}"
          Rails.logger.error("iPay#process!: #{error_msg}\n#{e.backtrace.join("\n")}")
          return failure_response("Failed to update payment amount")
        end
      else
        Rails.logger.debug("iPay#process!: No amount update needed (difference: #{amount_diff})")
      end

      # Store phone number in session if we have a controller context
      if options[:controller]&.respond_to?(:session)
        Rails.logger.debug("iPay#process!: Storing phone number in session")
        options[:controller].session[:ipay_phone_number] = phone_digits
      else
        Rails.logger.debug("iPay#process!: No controller context available for session storage")
      end

      # Final validation before completing processing
      begin
        Rails.logger.info("iPay#process!: Final payment validation")
        
        # Ensure payment is in the correct state
        unless payment.respond_to?(:started_processing!)
          error_msg = "Payment does not support started_processing! method"
          Rails.logger.error("iPay#process!: #{error_msg}")
          return failure_response("Payment processing error")
        end
        
        # Transition payment to processing state
        Rails.logger.info("iPay#process!: Transitioning payment to processing state")
        payment.started_processing!
        
        # Verify the state transition was successful
        if payment.state != 'processing' && payment.state != 'pending'
          error_msg = "Failed to transition payment to processing state. Current state: #{payment.state}"
          Rails.logger.error("iPay#process!: #{error_msg}")
          return failure_response("Payment processing error")
        end
        
        Rails.logger.info("iPay#process!: Payment processing started successfully. Current state: #{payment.state}")
        
        # Prepare success response with detailed payment information
        success_response('Payment processing started', {
          payment: {
            id: payment.id,
            number: payment.number,
            state: payment.state,
            amount: payment.amount.to_f,
            currency: payment.currency,
            payment_method_id: payment.payment_method_id,
            source_type: payment.source_type,
            source_id: payment.source_id,
            created_at: payment.created_at,
            updated_at: payment.updated_at
          },
          order: {
            id: payment.order.id,
            number: payment.order.number,
            state: payment.order.state,
            total: payment.order.total.to_f,
            currency: payment.order.currency,
            email: payment.order.email,
            user_id: payment.order.user_id
          },
          next_steps: {
            redirect_url: nil,  # Will be set by the controller
            poll_url: "/api/v1/ipay/status/#{payment.number}",
            callback_url: callback_url(payment)
          },
          metadata: {
            timestamp: Time.current.iso8601,
            request_id: options[:request_id],
            **((session_id = options.dig(:controller, :session, :session_id) if options[:controller]&.respond_to?(:session)) ? { session_id: session_id } : {})
          }.compact
        })
        
      rescue StandardError => e
        error_msg = "Error during final payment processing: #{e.message}"
        Rails.logger.error("iPay#process!: #{error_msg}\n#{e.backtrace.join("\n")}")
        failure_response("Payment processing failed: #{e.message}")
      end
    rescue StandardError => e
      error_msg = "Unexpected error in payment processing: #{e.message}"
      Rails.logger.error("iPay#process!: #{error_msg}\n#{e.backtrace.join("\n")}")
      failure_response("Payment processing failed. Please try again.")
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

      # Set live mode (0 for test, 1 for live)
      live = test_mode? ? "0" : "1"

      # Prepare values - must match exactly what will be sent in the form
      oid = payment.order.number.to_s.gsub(/[^a-zA-Z0-9]/, '')[0...26] # Max 26 alphanumeric chars
      inv = oid[0...15] # Max 15 chars, use order ID if not specified
      ttl = (payment.amount.to_f * 100).to_i.to_s # Amount in cents, no decimals
      tel = (phone.presence || payment.order.bill_address&.phone.to_s.presence || "0700000000").gsub(/\D/, '')[0...15] # Max 15 digits
      eml = payment.order.email.to_s[0...30] # Max 30 chars
      vid = vendor_id[0...12] # Max 12 chars
      curr = (preferred_currency.presence || 'KES')[0...3] # Max 3 chars
      p1 = ""
      p2 = ""
      p3 = ""
      p4 = ""
      cbk = (preferred_callback_url.presence || "https://#{base_url}/ipay/confirm").gsub(/[;:~`!%^*\-><&_]/i, '') # Remove invalid chars
      cst = "1"
      crl = "0" # 0 for HTTP/HTTPS callback

      # Create datastring in the exact order required by iPay
      # IMPORTANT: This exact order must be maintained
      datastring = live + oid + inv + ttl + tel + eml + vid + curr + p1 + p2 + p3 + p4 + cbk + cst + crl

      # Generate hash using OpenSSL to match PHP's hash_hmac('sha1', ...)
      digest = OpenSSL::Digest.new('sha1')
      hash = OpenSSL::HMAC.hexdigest(digest, hash_key, datastring)
      
      # Ensure the hash is lowercase to match PHP's output
      hash.downcase
    rescue StandardError => e
      raise "Error generating hash: #{e.message}"
    end

    def generate_ipay_form_html(payment)
      # Get required values
      live = test_mode? ? "0" : "1"
      # Use numeric order ID for transaction code
      oid = payment.order.id.to_s
      # Use numeric order ID for invoice as well
      inv = payment.order.id.to_s
      ttl = (payment.amount.to_f * 100).to_i.to_s # Amount in cents
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
      order_token = payment.order.guest_token
      rst = preferred_return_url.presence || "#{default_protocol}://#{default_host}/orders/#{order_number}?order_token=#{order_token}"

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

    def generate_hash(payment)
      # Prepare all values
      live = preferred_test_mode ? '0' : '1'
      oid = payment.order.number
      inv = payment.order.number
      ttl = payment.amount.to_f.round(2).to_s
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
      preferred_test_mode ? 'https://sandbox.ipayafrica.com/v3/ke' : 'https://payments.ipayafrica.com/v3/ke'
    end

    def success_response(message = 'Success', data = {})
      Rails.logger.debug("iPay#success_response: #{message}")
      
      # Prepare response data with defaults
      response_data = {
        success: true,
        message: message,
        test_mode: test_mode?,
        timestamp: Time.current.iso8601
      }.merge(data)
      
      # Log the response data (without sensitive information)
      log_data = response_data.dup
      log_data.delete(:hash_key) if log_data.key?(:hash_key)
      Rails.logger.debug("iPay#success_response data: #{log_data.inspect}")
      
      # Return the response object
      ActiveMerchant::Billing::Response.new(
        true,
        message,
        response_data,
        test: test_mode?
      )
    end

    def failure_response(message = 'Failed', error_details = {})
      Rails.logger.error("iPay#failure_response: #{message}")
      
      # Prepare error data with defaults
      error_data = {
        success: false,
        message: message,
        test_mode: test_mode?,
        timestamp: Time.current.iso8601,
        error_code: error_details[:code] || 'payment_error',
        error_details: error_details.except(:code)
      }
      
      # Log the error details (without sensitive information)
      log_data = error_data.dup
      log_data.delete(:hash_key) if log_data.key?(:hash_key)
      Rails.logger.error("iPay#failure_response details: #{log_data.inspect}")
      
      # Return the error response object
      ActiveMerchant::Billing::Response.new(
        false,
        message,
        error_data,
        test: test_mode?
      )
    end
  end
end
