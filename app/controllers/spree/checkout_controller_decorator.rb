module Spree
  # Decorates the Spree::CheckoutController to add iPay payment processing functionality.
  # Handles the payment form submission and redirection to iPay's payment page.
  # Manages the payment flow during the checkout process.
  module CheckoutControllerDecorator
    def self.prepended(base)
      base.before_action :log_checkout_state, only: [:update]
      base.before_action :handle_ipay_redirect, only: [:update]
      base.before_action :set_request_variant
      base.before_action :reset_incomplete_payment_if_any, only: [:update]
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
        Rails.logger.info("IPAY_DEBUG: [handle_ipay_redirect] State: #{params[:state]}, Order: #{@order&.number}")
        
        # Get phone number and store in session during payment state
        if params[:state] == "payment"
          phone = params.dig(:order, :payments_attributes, 0, :source_attributes, :phone)
          if phone.present?
            session[:ipay_phone_number] = phone
            Rails.logger.info("IPAY_DEBUG: [handle_ipay_redirect] Stored phone number in session")
          end
        end

        # Generate form and redirect during confirm state
        if params[:state] == "confirm" && @order.payments.last&.payment_method&.is_a?(Spree::PaymentMethod::Ipay)
          payment = @order.payments.last
          ipay_method = payment.payment_method
          phone = session[:ipay_phone_number] || @order.bill_address&.phone

          raise 'Phone number is required' if phone.blank?

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
      Rails.logger.info("IPAY_DEBUG: [generate_ipay_form_html] Payment: #{payment.number}, Order: #{payment.order.number}")
      
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
      
      Rails.logger.debug("IPAY_DEBUG: [generate_ipay_form_html] " \
                        "Order: #{oid}, " \
                        "Amount: #{payment.amount} #{curr}, " \
                        "Phone: #{tel}, " \
                        "Email: #{eml}, " \
                        "Test Mode: #{live == '1' ? 'No' : 'Yes'}")
      
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
    
    def update
      Rails.logger.info("IPAY_DEBUG: [update] Starting update for order #{@order.number} in state #{@order.state}")

      # Handle iPay payment specifically
      if @order.state == 'payment' && params[:state] == 'payment'
        payment_params = params.dig(:order, :payments_attributes, 0)
        if payment_params && payment_params[:payment_method_id].present?
          payment_method = Spree::PaymentMethod.find(payment_params[:payment_method_id])
          if payment_method.is_a?(Spree::PaymentMethod::Ipay)
            Rails.logger.info("IPAY_DEBUG: [update] Processing iPay payment for order #{@order.number}")
            
            # Create a new payment in processing state
            payment = @order.payments.create!(
              payment_method: payment_method,
              amount: @order.total,
              state: 'checkout'
            )
            
            # Process the payment with amount
            response = payment_method.process!(
              payment: payment,
              amount: @order.total,
              phone: payment_params.dig(:source_attributes, :phone),
              options: { controller: self }
            )
            
            if response.success?
              Rails.logger.info("IPAY_DEBUG: [update] iPay payment processing started for order #{@order.number}")
              
              # Move to the next state
              if @order.next
                Rails.logger.info("IPAY_DEBUG: [update] Moved order #{@order.number} to next state: #{@order.state}")
              else
                Rails.logger.error("IPAY_DEBUG: [update] Failed to move order #{@order.number} to next state. Errors: #{@order.errors.full_messages.join(', ')}")
              end

              session[:current_payment_id] = payment.id

              respond_to do |format|
                format.html { redirect_to checkout_state_path('confirm') }
                format.json { render json: { status: 'success', redirect: checkout_state_path('confirm') } }
              end
              return
            else
              flash[:error] = response.message
              redirect_to checkout_state_path('payment')
              return
            end
          end
        end
      end
      
      # Standard update flow for non-iPay payments
      if @order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
        @order.temporary_address = !params[:save_user_address]
        
        unless @order.next
          flash[:error] = @order.errors.full_messages.join("\n")
          redirect_to(checkout_state_path(@order.state)) && return
        end

        if @order.completed?
          @current_order = nil
          flash.notice = Spree.t(:order_processed_successfully)
          flash['order_completed'] = true
          redirect_to completion_route
        else
          respond_to do |format|
            format.html { redirect_to checkout_state_path(@order.state) }
            format.json do
              render json: {
                status: 'success',
                next_step: @order.state,
                order: {
                  number: @order.number,
                  state: @order.state,
                  total: @order.total.to_f,
                  payment_state: @order.payment_state,
                  shipment_state: @order.shipment_state
                }
              }
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
              message: @order.errors.full_messages.to_sentence
            }, status: :unprocessable_entity
          end
        end
      end
    end
    
    private
    
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
    
    def reset_incomplete_payment_if_any
      return unless @order.payment_required?
      
      # Log current order state for debugging
      Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Order[#{@order&.number || 'nil'}] " \
                       "State: #{@order.state}, " \
                       "Payment State: #{@order.payment_state}, " \
                       "Total: #{@order.total}, " \
                       "Line Items: #{@order.line_items.count}")
      
      # Check if the order was modified (items added/removed) after payment was initiated
      order_was_modified = @order.line_items.any? { |item| item.updated_at > 1.minute.ago }
      
      # Get all incomplete payments (include processing and pending payments)
      incomplete_payments = @order.payments.reject(&:completed?).reject(&:failed?).reject(&:void?)
      
      Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Found #{incomplete_payments.size} incomplete payments: " \
                       "#{incomplete_payments.map { |p| "#{p.number}:#{p.state}" }.join(', ')}")
      
      # If we have any incomplete payments or order was modified, handle them
      if incomplete_payments.any? || order_was_modified
        Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Processing #{incomplete_payments.count} incomplete payments " \
                         "and order_was_modified=#{order_was_modified} for order #{@order.number}")
        
        # Process all incomplete payments
        incomplete_payments.each do |payment|
          begin
            Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Processing payment: " \
                            "#{payment.number} (State: #{payment.state}, Amount: #{payment.amount})")
            
            # Skip if already void or invalid
            if payment.void? || payment.invalid?
              Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Skipping - " \
                              "Payment #{payment.number} is already #{payment.void? ? 'void' : 'invalid'}")
              next
            end
            
            # For processing payments, try to cancel them first
            if payment.processing?
              if payment.payment_method.respond_to?(:cancel)
                begin
                  Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Cancelling processing payment: #{payment.number}")
                  payment.payment_method.cancel(payment.response_code)
                  payment.update_columns(
                    state: 'void',
                    updated_at: Time.current
                  )
                  next
                rescue StandardError => e
                  Rails.logger.error("IPAY_DEBUG: [reset_incomplete_payment_if_any] Error cancelling payment #{payment.number}: " \
                                   "#{e.class}: #{e.message}")
                end
              else
                Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Payment method doesn't support cancellation, marking as failed: #{payment.number}")
                payment.update_columns(
                  state: 'failed',
                  updated_at: Time.current
                )
                next
              end
            end
            
            # Try to void the payment if it's voidable
            if payment.can_void?
              begin
                Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Voiding payment: #{payment.number}")
                payment.void_transaction!
              rescue StandardError => e
                Rails.logger.error("IPAY_DEBUG: [reset_incomplete_payment_if_any] Error voiding payment #{payment.number}: " \
                                 "#{e.class}: #{e.message}")
                # If void fails, try to mark as failed
                payment.update_columns(
                  state: 'failed',
                  updated_at: Time.current
                )
              end
            else
              Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Cannot void payment: " \
                              "#{payment.number} (State: #{payment.state})")
              # If we can't void, mark as failed
              payment.update_columns(
                state: 'failed',
                updated_at: Time.current
              )
            end
            
            # Skip invalidation if already failed or voided
            next if payment.failed? || payment.void?
            
            # Try to invalidate the payment
            if payment.can_invalidate?
              begin
                Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Invalidating payment: #{payment.number}")
                payment.invalidate!
              rescue StandardError => e
                Rails.logger.error("IPAY_DEBUG: [reset_incomplete_payment_if_any] Error invalidating payment #{payment.number}: " \
                                 "#{e.class}: #{e.message}")
                # If invalidation fails, mark as failed
                payment.update_columns(
                  state: 'failed',
                  updated_at: Time.current
                )
              end
            else
              Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Cannot invalidate payment: " \
                              "#{payment.number} (State: #{payment.state})")
              # If we can't invalidate, mark as failed
              payment.update_columns(
                state: 'failed',
                updated_at: Time.current
              )
            end
          rescue StandardError => e
            Rails.logger.error("IPAY_DEBUG: [reset_incomplete_payment_if_any] Error processing payment #{payment.number}: " \
                             "#{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
          end
        end
        
        # Reset order to payment state if not already there or if order was modified
        if @order.state != 'payment' || order_was_modified
          Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Resetting order #{@order.number} to payment state " \
                          "(order_was_modified=#{order_was_modified})")
          
          begin
            # Reset the order state
            @order.update_columns(
              state: 'payment',
              payment_state: 'balance_due',
              updated_at: Time.current
            )
            
            Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Order #{@order.number} reset to payment state " \
                            "with total: #{@order.total}")
            
            # If order was modified, log the changes
            if order_was_modified
              Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Order #{@order.number} was modified. " \
                              "New line items: #{@order.line_items.count}, New total: #{@order.total}")
            end
            
          rescue => e
            Rails.logger.error("IPAY_DEBUG: [reset_incomplete_payment_if_any] Failed to reset order state: " \
                             "#{e.class}: #{e.message}")
            raise
          end
          
          # Create a new checkout payment if we don't have any valid ones or if order was modified
          if @order.payments.valid.none? || order_was_modified
            last_payment = @order.payments.last
            if last_payment&.payment_method
              begin
                # Create a new payment with the updated amount
                new_payment = @order.payments.create!(
                  payment_method_id: last_payment.payment_method_id,
                  amount: @order.outstanding_balance,
                  state: 'checkout'
                )
                Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Created new checkout payment: " \
                                "#{new_payment.number} (Amount: #{new_payment.amount})")
              rescue => e
                Rails.logger.error("IPAY_DEBUG: [reset_incomplete_payment_if_any] Failed to create new payment: " \
                                 "#{e.class}: #{e.message}")
                raise
              end
            else
              Rails.logger.warn("IPAY_DEBUG: [reset_incomplete_payment_if_any] No valid payment method found " \
                               "for order #{@order.number}")
            end
          else
            Rails.logger.debug("IPAY_DEBUG: [reset_incomplete_payment_if_any] Valid payments exist, not creating new one")
          end
          
          # Redirect to payment step to ensure proper state handling
          if params[:state] != 'payment' && request.get?
            Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Redirecting to payment step")
            redirect_to checkout_state_path('payment') and return
          else
            Rails.logger.debug("IPAY_DEBUG: [reset_incomplete_payment_if_any] No redirect needed - " \
                             "params[:state]: #{params[:state]}, request.get?: #{request.get?}")
          end
        end
      end
      
      # If we're in the confirm state but don't have a valid payment, go back to payment
      if @order.state == 'confirm' && @order.payments.valid.none?
        Rails.logger.warn("IPAY_DEBUG: [reset_incomplete_payment_if_any] Order #{@order.number} in confirm state " \
                         "without valid payments, resetting to payment state")
        
        begin
          @order.update_columns(
            state: 'payment',
            payment_state: 'balance_due',
            updated_at: Time.current
          )
          Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Order #{@order.number} reset to payment state")
          
          if request.get?
            Rails.logger.info("IPAY_DEBUG: [reset_incomplete_payment_if_any] Redirecting to payment step")
            redirect_to checkout_state_path('payment') and return
          end
        rescue => e
          Rails.logger.error("IPAY_DEBUG: [reset_incomplete_payment_if_any] Failed to reset order state: " \
                           "#{e.class}: #{e.message}")
          raise
        end
      end
    end
  end
end

::Spree::CheckoutController.prepend Spree::CheckoutControllerDecorator
