# frozen_string_literal: true

module Spree
  module IpayControllerDecorator
    def self.prepended(base)
      base.respond_to :html, :json
      base.before_action :set_headers
      base.around_action :handle_json_format, only: [:interactive_checkout, :callback]
    end

    def interactive_checkout
      @order = Spree::Order.find_by!(number: params[:id])
      
      # Get stored session data
      phone = session[:ipay_phone_number]
      redirect_url = session[:ipay_redirect_url]
      
      respond_to do |format|
        format.html do
          if redirect_url.present?
            # Clear session data
            session.delete(:ipay_phone_number)
            session.delete(:ipay_redirect_url)
            
            redirect_to redirect_url, allow_other_host: true
          else
            redirect_to checkout_state_path(@order.state), 
                        alert: "Unable to process payment. Please try again."
          end
        end
        
        format.json do
          if redirect_url.present?
            render json: {
              status: 'success',
              redirect_url: redirect_url,
              order: {
                id: @order.id,
                number: @order.number,
                state: @order.state,
                total: @order.total.to_f
              }
            }
          else
            render json: {
              status: 'error',
              message: 'Unable to process payment. Please try again.'
            }, status: :unprocessable_entity
          end
        end
      end
    rescue ActiveRecord::RecordNotFound => e
      respond_to do |format|
        format.html { redirect_to cart_path, alert: "Order not found." }
        format.json { render json: { status: 'error', message: 'Order not found' }, status: :not_found }
      end
    rescue => e
      respond_to do |format|
        format.html do
          redirect_to checkout_state_path(@order&.state || :cart), 
                      alert: "An error occurred while processing your payment. Please try again."
        end
        format.json do
          render json: { 
            status: 'error', 
            message: 'An error occurred while processing your payment',
            error: Rails.env.development? ? e.message : nil
          }, status: :internal_server_error
        end
      end
    end

    private

    def set_headers
      response.headers['Cache-Control'] = 'no-cache, no-store, max-age=0, must-revalidate'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = 'Fri, 01 Jan 1990 00:00:00 GMT'
    end

    def handle_json_format
      if request.format.json?
        begin
          yield
        rescue => e
          render json: { 
            status: 'error', 
            message: e.message,
            backtrace: Rails.env.development? ? e.backtrace : nil
          }, status: :internal_server_error
        end
      else
        yield
      end
    end
  end
end

Spree::IpayController.prepend(Spree::IpayControllerDecorator) if defined?(Spree::IpayController)
