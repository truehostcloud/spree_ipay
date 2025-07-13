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
      # Get phone number and store in session during payment state
      if params[:state] == "payment"
        phone = params.dig(:order, :payments_attributes, 0, :source_attributes, :phone)
        session[:ipay_phone_number] = phone if phone.present?
        return # Continue with normal flow for payment state
      end

      # Only handle confirm state for iPay payments
      return unless params[:state] == "confirm" && @order.payments.last&.payment_method&.is_a?(Spree::PaymentMethod::Ipay)
      
      payment = @order.payments.last
      ipay_method = payment.payment_method
      phone = session[:ipay_phone_number] || @order.bill_address.phone
      
      # Set instance variables for the view
      @payment = payment
      @ipay_method = ipay_method
      @phone = phone

      # For AJAX/JSON requests, return the form HTML
      if request.xhr? || request.format.json?
        render json: {
          status: 'redirect',
          redirect_url: checkout_state_path(:confirm),
          message: 'Please wait, redirecting to payment...'
        }
      else
        # For regular HTML requests, render the redirect page
        render 'spree/checkout/ipay_redirect', layout: 'spree/layouts/checkout'
      end
      return false # Prevent further processing
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
      # This method is kept for backward compatibility but now uses the partial
      render_to_string(
        partial: 'spree/checkout/ipay_form',
        formats: [:html],
        layout: false,
        locals: {
          payment: payment,
          ipay_method: ipay_method,
          phone: phone
        }
      )
    rescue StandardError => e
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
