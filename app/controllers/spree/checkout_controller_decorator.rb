module Spree
  # Decorates the Spree::CheckoutController to add iPay payment processing functionality.
  # Handles the payment form submission and redirection to iPay's payment page.
  # Manages the payment flow during the checkout process.
  module CheckoutControllerDecorator
    def self.prepended(base)
      base.before_action :log_checkout_state, only: [:update]
      base.before_action :handle_ipay_redirect, only: [:update]
      base.before_action :set_request_variant
    end
    
    def log_checkout_state
      # No logging needed
    end

    # Set request variant based on format
    def set_request_variant
      request.variant = :api if request.format.json?
    end

    def handle_ipay_redirect
      # Skip if not in the confirm state or not an iPay payment
      return unless params[:state] == "confirm" && @order.payments.last&.payment_method&.is_a?(Spree::PaymentMethod::Ipay)
      
      payment = @order.payments.last
      ipay_method = payment.payment_method
      phone = session[:ipay_phone_number] || @order.bill_address&.phone || '0700000000'
      
      # Skip if we've already redirected to iPay
      return if request.referer&.include?('payments.ipayafrica.com')
      
      respond_to do |format|
        format.html do
          # If this is a POST request, it means we're coming from the payment step
          if request.post?
            # Store the order in the session in case we need to redirect back
            session[:order_id] = @order.id
            
            # Render the iPay form with auto-submit
            render html: generate_ipay_form_html(payment, phone, ipay_method).html_safe, 
                   layout: 'spree/layouts/checkout',
                   status: :ok
          else
            # If it's a GET request, redirect to the payment step first
            redirect_to checkout_state_path(:payment) and return
          end
        end
        format.json do
          render json: {
            status: 'success',
            next_step: 'confirm',
            form_html: generate_ipay_form_html(payment, phone, ipay_method)
          }, status: :ok
        end
      end
      
      # Prevent further processing
      throw :abort
      
    rescue StandardError => e
      Rails.logger.error "iPay redirect error: #{e.message}\n#{e.backtrace.join("\n")}"
      
      respond_to do |format|
        format.html do
          redirect_to checkout_state_path(:payment), 
                    error: "Payment processing failed: #{e.message}",
                    status: :see_other
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
      # Get required values from payment method preferences
      live = ipay_method.preferred_test_mode ? '0' : '1'
      oid = payment.order.number
      inv = "#{payment.order.number}#{Time.now.to_i}" # unique invoice
      ttl = (payment.amount.to_f * 100).to_i.to_s # Amount in cents
      eml = payment.order.email
      vid = ipay_method.preferred_vendor_id.presence || ''
      curr = ipay_method.preferred_currency.presence || 'KES'
      p1 = p2 = p3 = p4 = ""
      cbk = ipay_method.preferred_callback_url.presence || "https://example.com/ipay/callback"
      cst = "1"
      crl = "2"

      # Generate the hash with the phone number
      hsh = ipay_method.ipay_signature_hash(payment, phone)

      # Prepare iPay parameters
      ipay_params = {
        'live' => live,
        'oid' => oid,
        'inv' => inv,
        'ttl' => ttl,
        'tel' => phone || '0700000000',
        'eml' => eml,
        'vid' => vid,
        'curr' => curr,
        'p1' => p1,
        'p2' => p2,
        'p3' => p3,
        'p4' => p4,
        'cbk' => cbk,
        'cst' => cst,
        'crl' => crl,
        'hsh' => hsh
      }

      # Add channel parameters
      %i[mpesa bonga airtel equity mobilebanking creditcard unionpay mvisa vooma pesalink autopay].each do |channel|
        ipay_params[channel.to_s] = ipay_method.preferences[channel.to_s] ? '1' : '0'
      end

      # Build the form using content_tag
      form = content_tag(:form, 
        id: 'ipay-payment-form',
        action: ipay_method.preferred_test_mode ? 'https://payments.ipayafrica.com/v3/ke' : 'https://payments.ipayafrica.com/v3/ke',
        method: 'post',
        class: 'flex justify-center'
      ) do
        safe_join(
          ipay_params.map { |k, v| hidden_field_tag(k, v) } +
          [content_tag(:button, 'Proceed to Payment', 
                      type: 'submit', 
                      class: 'bg-blue-600 text-white font-semibold py-2 px-4 rounded-md hover:bg-blue-700 transition duration-300')]
        )
      end

      # Build the loading spinner
      spinner = content_tag(:div, class: 'flex justify-center') do
        content_tag(:svg, 
          class: 'animate-spin h-14 w-14 text-blue-600', 
          xmlns: 'http://www.w3.org/2000/svg', 
          fill: 'none', 
          viewBox: '0 0 24 24'
        ) do
          content_tag(:circle, '', 
            class: 'opacity-25', 
            cx: '12', 
            cy: '12', 
            r: '10', 
            stroke: 'currentColor', 
            'stroke-width': '4'
          ) + 
          content_tag(:path, '', 
            class: 'opacity-75', 
            fill: 'currentColor', 
            d: 'M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z'
          )
        end
      end

      # Build the complete HTML
      content_tag(:div, class: 'bg-white rounded-xl shadow-xl w-full max-w-3xl mx-auto p-6 sm:p-8 flex flex-col justify-center space-y-6') do
        spinner +
        content_tag(:h2, 'Redirecting to iPay', class: 'text-3xl sm:text-4xl font-extrabold text-gray-800 text-center') +
        content_tag(:p, 'Please wait while we securely redirect you to the payment page.', class: 'text-gray-600 text-lg sm:text-xl text-center') +
        content_tag(:p, 'If you are not redirected automatically, please click the button below.', class: 'text-sm sm:text-base text-gray-500 text-center') +
        form +
        javascript_tag(nonce: true) do
          "document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
              document.getElementById('ipay-payment-form').submit();
            }, 1000);
          });".html_safe
        end
      end
    rescue StandardError => e
      raise "Error generating payment form: #{e.message}"
    end
    # Override update action to handle JSON responses and iPay payment flow
    def update
      # Handle iPay payment method selection
      if params[:state] == 'payment' && params[:order] && params[:order][:payments_attributes]
        payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
        if payment_method.is_a?(Spree::PaymentMethod::Ipay)
          # Store phone number in session for iPay
          phone = params.dig(:order, :payments_attributes, 0, :source_attributes, :phone)
          session[:ipay_phone_number] = phone if phone.present?
        end
      end

      if @order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
        respond_to do |format|
          format.html do
            if @order.next
              # If next state is confirm and payment method is iPay, handle specially
              if @order.state == 'confirm' && @order.payments.last&.payment_method&.is_a?(Spree::PaymentMethod::Ipay)
                # Let the before_action handle the iPay redirect
                redirect_to checkout_state_path(@order.state) and return
              else
                redirect_to checkout_state_path(@order.state)
              end
            else
              redirect_to checkout_state_path(@order.state)
            end
          end
          
          format.json do
            if @order.next
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
                
                # If it's iPay, add the form HTML to the response
                if payment.payment_method.is_a?(Spree::PaymentMethod::Ipay)
                  phone = session[:ipay_phone_number] || @order.bill_address&.phone
                  response_data[:form_html] = generate_ipay_form_html(payment, phone, payment.payment_method)
                end
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
  end
end

::Spree::CheckoutController.prepend Spree::CheckoutControllerDecorator
