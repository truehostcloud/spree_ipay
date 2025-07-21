module Spree
  # Decorates the Spree::CheckoutController to add iPay payment processing functionality.
  # Handles the payment form submission and redirection to iPay's payment page.
  # Manages the payment flow during the checkout process.
  module CheckoutControllerDecorator
    def self.prepended(base)
      base.before_action :log_checkout_state, only: [:update]
      base.before_action :handle_ipay_redirect, only: [:update]
      base.before_action :set_request_variant
      base.before_action :handle_pending_ipay_payment, only: [:edit], if: -> { @order&.payment? }
    end
    
    def log_checkout_state
      # No logging needed
    end

    # Set request variant based on format
    def set_request_variant
      request.variant = :api if request.format.json?
    end

    def handle_ipay_redirect
      begin
        Rails.logger.info "omkuu: [Checkout] ====== HANDLE IPAY REDIRECT ======"
        Rails.logger.info "omkuu: [Checkout] Current state: #{params[:state]}, Order: #{@order&.number}"
        
        # Get phone number and store in session during payment state
        if params[:state] == "payment"
          Rails.logger.info "omkuu: [Checkout] ====== PROCESSING PAYMENT STATE ======"
          
          # Log order state and payments before making any changes
          log_order_payments("Before payment processing")
          
          # Extract phone number from params
          phone = params.dig(:order, :payments_attributes, 0, :source_attributes, :phone)
          if phone.present?
            Rails.logger.info "omkuu: [Checkout] Storing phone number in session: #{phone}"
            session[:ipay_phone_number] = phone
          else
            Rails.logger.warn "omkuu: [Checkout] No phone number provided in params"
            # Try to get phone from order if not in params
            phone = @order.bill_address&.phone if @order.bill_address
            session[:ipay_phone_number] = phone if phone.present?
          end
          
          # Ensure we have a payment method
          payment_method = Spree::PaymentMethod.find_by(type: 'Spree::PaymentMethod::Ipay', active: true)
          unless payment_method
            error_msg = 'Active iPay payment method not found. Please enable iPay payment method in admin.'
            Rails.logger.error "omkuu: [Checkout] #{error_msg}"
            flash[:error] = error_msg
            redirect_to checkout_state_path(@order.state) and return
          end
          
          # Create a new payment if none exists
          if @order.payments.empty?
            Rails.logger.info "omkuu: [Checkout] No payments exist, creating new payment"
            begin
              payment = @order.payments.build(
                payment_method: payment_method,
                amount: @order.total,
                response_code: "IPAY_#{Time.now.to_i}",
                state: 'checkout'
              )
              
              if payment.save
                Rails.logger.info "omkuu: [Checkout] Successfully created payment: #{payment.id}"
                @order.reload
              else
                Rails.logger.error "omkuu: [Checkout] Failed to create payment: #{payment.errors.full_messages.join(', ')}"
                raise "Failed to create payment: #{payment.errors.full_messages.join(', ')}"
              end
            rescue StandardError => e
              error_msg = "Error creating payment: #{e.message}"
              Rails.logger.error "omkuu: [Checkout] #{error_msg}"
              flash[:error] = "Unable to process payment. Please try again."
              redirect_to checkout_state_path(@order.state) and return
            end
          end
          
          # Ensure we have a valid payment
          payment = @order.payments.last
          unless payment
            error_msg = 'No payment found for this order'
            Rails.logger.error "omkuu: [Checkout] #{error_msg}"
            flash[:error] = error_msg
            redirect_to checkout_state_path(@order.state) and return
          end
          
          # Log payment details
          Rails.logger.info "omkuu: [Checkout] Current payment ID: #{payment.id}, State: #{payment.state}"
          
          # Invalidate any existing pending payments for this order
          Rails.logger.info "omkuu: [Checkout] Invalidating existing payments"
          invalidate_existing_payments
          
          log_order_payments("After payment processing")
          
          # Ensure we have a phone number for the payment
          unless session[:ipay_phone_number].present? || @order.bill_address&.phone.present?
            error_msg = 'Phone number is required for iPay payment'
            Rails.logger.error "omkuu: [Checkout] #{error_msg}"
            flash[:error] = 'Please provide a valid phone number for payment'
            redirect_to checkout_state_path('payment') and return
          end
          
          # If we get here, we're ready to proceed to confirm
          Rails.logger.info "omkuu: [Checkout] Payment processing complete, proceeding to confirm"
          
        end

        # Generate form and redirect during confirm state
        if params[:state] == "confirm"
          Rails.logger.info "omkuu: [Checkout] ====== PROCESSING CONFIRM STATE ======"
          
          # Ensure we have an iPay payment method
          payment_method = Spree::PaymentMethod.find_by(type: 'Spree::PaymentMethod::Ipay')
          unless payment_method
            error_msg = 'iPay payment method not found'
            Rails.logger.error "omkuu: [Checkout] #{error_msg}"
            raise error_msg
          end
          
          # Get or create payment
          payment = @order.payments.where(payment_method: payment_method).last
          
          # Create a new payment if none exists or if existing payment is in a terminal state
          if payment.nil? || payment.completed? || payment.failed? || payment.void?
            Rails.logger.info "omkuu: [Checkout] Creating new payment (existing: #{payment&.id}, state: #{payment&.state})"
            
            payment = @order.payments.create!(
              payment_method: payment_method,
              amount: @order.total,
              response_code: "IPAY_#{Time.now.to_i}",
              state: 'checkout'
            )
            
            Rails.logger.info "omkuu: [Checkout] Created new payment ID: #{payment.id}"
            
            # Invalidate any other pending payments
            invalidate_existing_payments
          end
          
          Rails.logger.info "omkuu: [Checkout] Using payment ID: #{payment.id}, state: #{payment.state}"
          
          # Get phone number from session or order
          phone = session[:ipay_phone_number] || @order.bill_address&.phone
          
          unless phone.present?
            error_msg = 'Phone number is required for iPay payment'
            Rails.logger.error "omkuu: [Checkout] #{error_msg}"
            raise error_msg
          end

          respond_to do |format|
            format.html do
              # Generate and render the iPay form immediately
              render html: generate_ipay_form_html(payment, phone, ipay_method).html_safe, layout: 'spree/layouts/checkout'
            end
            format.json do
              render json: {
                status: 'success',
                next_step: 'confirm',
                form_html: generate_ipay_form_html(payment, phone, ipay_method)
              }
            end
          end
          return false # Prevent further processing
        end
      rescue => e
        if Rails.env.development?
          Rails.logger.error("iPay Redirect Error: #{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
        else
          Rails.logger.error("iPay Redirect Error: #{e.class}: #{e.message}")
        end
        
        error_message = Rails.env.development? ? e.message : 'Unable to process payment. Please try again.'
        
        respond_to do |format|
          format.html { redirect_to checkout_state_path(@order.state), error: error_message }
          format.json { render json: { status: 'error', message: error_message }, status: :unprocessable_entity }
        end
      end
    rescue StandardError => e
      respond_to do |format|
        format.html do
          redirect_to checkout_state_path(:payment), error: "Payment processing failed: #{e.message}"
        end
        format.json do
          render json: {
            status: 'error',
            message: "Payment processing failed: #{e.message}",
            errors: [e.message]
          }, status: :unprocessable_entity
        end
      end
    end

    def generate_ipay_form_html(payment, phone, ipay_method)
      # Generate the hash with the phone number first (this also validates and formats our values)
      hsh = ipay_method.ipay_signature_hash(payment, phone)
      
      # Get values from payment method preferences
      live = ipay_method.preferred_test_mode ? '0' : '1'
      oid = payment.order.number.to_s.gsub(/[^a-zA-Z0-9]/, '')[0...26] # Max 26 alphanumeric chars
      inv = oid[0...15] # Max 15 chars, use order ID if not specified
      ttl = (payment.amount.to_f * 100).to_i.to_s # Amount in cents, no decimals
      tel = (phone.presence || payment.order.bill_address&.phone.to_s.presence || "0700000000").gsub(/\D/, '')[0...15] # Max 15 digits
      eml = payment.order.email.to_s[0...30] # Max 30 chars
      vid = (ipay_method.preferred_vendor_id.presence || '').downcase[0...12] # Max 12 chars, lowercase
      curr = (ipay_method.preferred_currency.presence || 'KES')[0...3] # Max 3 chars
      
      # Prepare callback URL - remove any invalid characters
      cbk = (ipay_method.preferred_callback_url.presence || "https://#{ipay_method.base_url}/ipay/callback").gsub(/[;:~`!%^*\-><&_]/i, '')
      
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
        'p1' => '',
        'p2' => '',
        'p3' => '',
        'p4' => '',
        'cbk' => cbk,
        'lbk' => cbk, # Use same as callback for simplicity
        'cst' => '1', # 1 = send customer email notifications
        'crl' => '0', # 0 = HTTP/HTTPS callback
        'hsh' => hsh
      }

      # Add channel parameters based on preferences
      %w[mpesa bonga airtel equity mobilebanking creditcard unionpay mvisa vooma pesalink autopay].each do |channel|
        # Use the proper preference accessor method
        preference_method = "preferred_#{channel}"
        is_enabled = if ipay_method.respond_to?(preference_method)
                      ipay_method.send(preference_method)
                    else
                      # Fallback to default (mpesa enabled, others disabled)
                      channel == 'mpesa'
                    end
        ipay_params[channel] = is_enabled ? '1' : '0'
        
        # Log each channel's status for debugging
        Rails.logger.info("iPay Channel #{channel}: #{is_enabled ? 'ENABLED' : 'DISABLED'}")
      end

      # Log the parameters being sent to iPay (remove in production)
      Rails.logger.info("iPay Form Parameters: #{ipay_params.to_json}")
      Rails.logger.info("iPay Test Mode: #{ipay_method.preferred_test_mode ? 'Yes' : 'No'}")
      Rails.logger.info("iPay Form Action: #{ipay_method.preferred_test_mode ? 'https://sandbox.ipayafrica.com/v3/ke' : 'https://payments.ipayafrica.com/v3/ke'}")

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
            <form id="ipay-payment-form" action="#{ipay_method.preferred_test_mode ? 'https://sandbox.ipayafrica.com/v3/ke' : 'https://payments.ipayafrica.com/v3/ke'}" method="post" class="flex justify-center">
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
    rescue StandardError => e
      Rails.logger.error("Error generating iPay form: #{e.message}\n#{e.backtrace.join("\n")}")
      raise "Error generating payment form: #{e.message}"
    end
    # Override update action to handle JSON responses
    def update
      if @order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
        respond_to do |format|
          format.html do
            if @order.next
              redirect_to checkout_state_path(@order.state)
            else
              redirect_to checkout_state_path(@order.state)
            end
          end
          
          format.json do
            if @order.next
              # Get the next state after the transition
              next_state = @order.state
              
              # Prepare response data
              response_data = {
                status: 'success',
                next_step: next_state,
                order: {
                  number: @order.number,
                  state: @order.state,
                  total: @order.total.to_f,
                  payment_state: @order.payment_state,
                  shipment_state: @order.shipment_state
                },
                payment_required: @order.payment_required?,
                checkout_steps: @order.checkout_steps,
                current_step: next_state,
                next_step_url: next_step_url_for(@order, next_state)
              }
              
              # Add payment info if in payment state
              if next_state == 'payment' && @order.payments.any?
                payment = @order.payments.last
                response_data[:payment] = {
                  id: payment.id,
                  number: payment.number,
                  state: payment.state,
                  amount: payment.amount.to_f,
                  payment_method_id: payment.payment_method_id,
                  payment_method_type: payment.payment_method&.type
                }
              end
              
              render json: response_data
            else
              render json: {
                status: 'error',
                errors: @order.errors.messages,
                message: @order.errors.full_messages.to_sentence
              }, status: :unprocessable_entity
            end
          end
        end
      else
        respond_to do |format|
          format.html { render :edit }
          format.json do
            render json: {
              status: 'error',
              errors: @order.errors.messages,
              message: @order.errors.full_messages.to_sentence,
              validation_errors: @order.errors.full_messages
            }, status: :unprocessable_entity
          end
        end
      end
    end
    
    private
    
    # Log detailed information about order payments
    def log_order_payments(context = "")
      return unless @order
      
      Rails.logger.info "omkuu: [Checkout] ====== ORDER PAYMENTS #{context} ======"
      Rails.logger.info "omkuu: [Checkout] Order: #{@order.number}, State: #{@order.state}"
      
      # Log order attributes
      Rails.logger.info "omkuu: [Checkout] Order state: #{@order.state}, " \
                       "Payment state: #{@order.payment_state}, " \
                       "Shipment state: #{@order.shipment_state}"
      
      # Log all payments
      Rails.logger.info "omkuu: [Checkout] Found #{@order.payments.count} payments"
      
      @order.payments.each_with_index do |payment, i|
        Rails.logger.info "omkuu: [Checkout] Payment #{i+1}: " \
                         "ID: #{payment.id}, " \
                         "Type: #{payment.payment_method&.type}, " \
                         "State: #{payment.state}, " \
                         "Amount: #{payment.amount}, " \
                         "Created: #{payment.created_at}"
      end
      
      # Log payment methods
      payment_methods = Spree::PaymentMethod.available(:both)
      Rails.logger.info "omkuu: [Checkout] Available payment methods: #{payment_methods.map(&:type).join(', ')}"
      
      Rails.logger.info "omkuu: [Checkout] ====== END ORDER PAYMENTS ======"
    end
    
    # Invalidate existing payments for this order
    def invalidate_existing_payments
      Rails.logger.info "omkuu: [Checkout] ====== STARTING PAYMENT INVALIDATION ======"
      
      unless @order
        Rails.logger.error "omkuu: [Checkout] No order found for payment invalidation"
        return
      end
      
      Rails.logger.info "omkuu: [Checkout] Order: #{@order.number}, State: #{@order.state}"
      
      # Debug order state and payments
      Rails.logger.info "omkuu: [Checkout] Order payments count: #{@order.payments.count}"
      @order.payments.each_with_index do |p, i|
        Rails.logger.info "omkuu: [Checkout] Payment #{i+1}: ID: #{p.id}, " \
                         "Method: #{p.payment_method&.type}, " \
                         "State: #{p.state}, " \
                         "Amount: #{p.amount}"
      end
      
      # Get all iPay payments for this order
      all_payments = @order.payments
                         .joins(:payment_method)
                         .where(spree_payment_methods: { type: 'Spree::PaymentMethod::Ipay' })
                         .order(created_at: :desc)
      
      Rails.logger.info "omkuu: [Checkout] Found #{all_payments.count} iPay payments"
      
      # Log all payments for debugging
      all_payments.each_with_index do |p, i|
        Rails.logger.info "omkuu: [Checkout] iPay Payment #{i+1}: " \
                         "ID: #{p.id}, " \
                         "State: #{p.state}, " \
                         "Amount: #{p.amount}, " \
                         "Created: #{p.created_at}, " \
                         "Updated: #{p.updated_at}, " \
                         "Checkout: #{p.checkout?}, " \
                         "Pending: #{p.pending?}, " \
                         "Completed: #{p.completed?}"
      end
      
      # Find payments to invalidate (exclude completed, void, failed, invalid)
      payments_to_invalidate = all_payments.reject do |p|
        p.completed? || p.void? || p.state == 'invalid' || p.state == 'failed' || p.state == 'errored'
      end
      
      Rails.logger.info "omkuu: [Checkout] Found #{payments_to_invalidate.count} payments to invalidate"
      
      if payments_to_invalidate.empty?
        Rails.logger.info "omkuu: [Checkout] No payments to invalidate"
        return
      end
      
      # Process each payment
      payments_to_invalidate.each do |payment|
        begin
          Rails.logger.info "omkuu: [Checkout] ====== PROCESSING PAYMENT #{payment.id} ======"
          Rails.logger.info "omkuu: [Checkout] Current state: #{payment.state}, Amount: #{payment.amount}"
          
          # Double check state
          if payment.completed? || payment.void? || payment.state == 'invalid' || payment.state == 'failed'
            Rails.logger.info "omkuu: [Checkout] Payment #{payment.id} already in final state: #{payment.state}, skipping"
            next
          end
          
          # Try to void the payment
          begin
            unless payment.void?
              Rails.logger.info "omkuu: [Checkout] Voiding payment #{payment.id}"
              payment.void_transaction! rescue nil # Continue even if void fails
            end
            
            # Direct SQL update to ensure state change
            Rails.logger.info "omkuu: [Checkout] Marking payment #{payment.id} as invalid"
            result = payment.class.connection.execute(
              "UPDATE spree_payments SET state = 'invalid', updated_at = NOW() WHERE id = #{payment.id}"
            )
            
            # Reload to verify
            payment.reload
            Rails.logger.info "omkuu: [Checkout] Payment #{payment.id} new state: #{payment.state}"
            
            if payment.state == 'invalid'
              Rails.logger.info "omkuu: [Checkout] Successfully invalidated payment #{payment.id}"
            else
              Rails.logger.error "omkuu: [Checkout] Failed to invalidate payment #{payment.id} - State is #{payment.state}"
            end
            
          rescue StandardError => e
            Rails.logger.error "omkuu: [Checkout] ERROR updating payment #{payment.id}: #{e.class} - #{e.message}"
            Rails.logger.error "omkuu: [Checkout] Backtrace: #{e.backtrace.first(5).join("\n")}"
          end
          
        rescue StandardError => e
          Rails.logger.error "omkuu: [Checkout] FATAL ERROR processing payment #{payment.id}: #{e.class} - #{e.message}"
          Rails.logger.error "omkuu: [Checkout] Backtrace: #{e.backtrace.first(5).join("\n")}"
        end
      end
    end
    
    def next_step_url_for(order, next_step)
      return unless next_step
      
      case next_step
      when 'address'
        checkout_state_path('address')
      when 'delivery'
        checkout_state_path('delivery')
      when 'payment'
        checkout_state_path('payment')
      when 'confirm'
        checkout_state_path('confirm')
      when 'complete'
        order_path(order, order_token: order.guest_token)
      end
    end
    
    private
    
    def handle_pending_ipay_payment
      return unless @order.payments.valid.iPay.any? { |p| p.checkout? && p.source&.status == 'pending' }
      
      flash[:notice] = I18n.t('spree.please_complete_payment')
      redirect_to checkout_state_path('payment')
    end
  end
end

::Spree::CheckoutController.prepend Spree::CheckoutControllerDecorator
