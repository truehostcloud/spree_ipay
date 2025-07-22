module Spree
  # Handles callbacks from the iPay payment gateway.
  # Processes payment confirmations and updates order statuses based on iPay responses.
  # This controller skips CSRF protection for the confirm action to allow external callbacks.
  class GatewayCallbacksController < ApplicationController
    layout false # Don't use the application layout
    skip_before_action :verify_authenticity_token, only: [:confirm, :callback]

    # GET /ipay/confirm - browser redirect confirmation page (no params expected)
    def confirm
      Rails.logger.info("[iPay CALLBACK PARAMS] #{params.to_unsafe_h}")
      Rails.logger.info("[iPay CALLBACK PARAMS] order_id: #{params[:order_id]}, id: #{params[:id]}, ivm: #{params[:ivm]}, oid: #{params[:oid]}")
      # This page is for user confirmation only. Do not update order/payment here.
      render 'success', status: :ok
    end

    # POST /ipay/callback - iPay server-to-server callback (full payment/order params expected)
    def callback
      Rails.logger.info("[iPay SERVER CALLBACK PARAMS] #{params.to_unsafe_h}")
      txn_id = params[:txnid]
      status = params[:status]
      # Check which param actually contains the order number from the log above
      order_number = params[:order_id] || params[:id] || params[:ivm] || params[:oid]

      order = Spree::Order.find_by(number: order_number)
      unless order
        render plain: "Order not found", status: :not_found
        return
      end

      payment = order.payments.last
      unless payment
        render plain: "Payment not found", status: :not_found
        return
      end

      # --- iPay C2B SHA1 HMAC Signature Verification ---
      required_keys = %w[live oid inv ttl tel eml vid curr p1 p2 p3 p4 cbk cst crl]
      # Accept both string and symbol keys from params
      param_values = required_keys.map { |k| params[k] || params[k.to_sym] }
      if param_values.all?
        datastring = param_values.join
        hash_key = payment.payment_method.preferred_hash_key if payment.payment_method.respond_to?(:preferred_hash_key)
        received_signature = params[:hsh] || params[:hash]
        generated_signature = OpenSSL::HMAC.hexdigest('sha1', hash_key, datastring)
        unless ActiveSupport::SecurityUtils.secure_compare(generated_signature, received_signature.to_s)
          render plain: "Invalid signature", status: :unauthorized
          return
        end
      end

      # --- Amount Verification ---
      paid_amount = params['mc'].to_f
      required_amount = order.total.to_f
      if paid_amount < required_amount
        Spree::Ipay::Logger.error("Amount paid (#{paid_amount}) is less than order total (#{required_amount})", order.number)
        render plain: "Amount paid (#{paid_amount}) is less than required (#{required_amount})", status: :payment_required
        return
      end

      # iPay status code handling (see docs)
      status_map = {
        'aei7p7yrx4ae34' => { label: 'Success', color: '#3bb143', icon: 'success', heading: 'Order Placed Successfully!' },
        'fe2707etr5s4wq' => { label: 'Failed', color: '#d32f2f', icon: 'fail', heading: 'Payment Failed' },
        'bdi6p2yy76etrs' => { label: 'Pending', color: '#fbc02d', icon: 'pending', heading: 'Payment Pending' },
        'cr5i3pgy9867e1' => { label: 'Used', color: '#d32f2f', icon: 'fail', heading: 'Code Already Used' },
        'dtfi4p7yty45wq' => { label: 'Less', color: '#d32f2f', icon: 'fail', heading: 'Insufficient Payment' },
        'eq3i7p5yt7645e' => { label: 'More', color: '#1976d2', icon: 'info', heading: 'Overpayment' }
      }
      code = status.to_s
      meta = status_map[code] || { label: 'Unknown', color: '#d32f2f', icon: 'fail', heading: 'Payment Failed' }
      message = params[:message] || 'There was an issue processing your payment.'
      msisdn_id = params[:msisdn_id] || ''
      msisdn_idnum = params[:msisdn_idnum] || ''

      # State handling
      if code == 'aei7p7yrx4ae34'
        payment.update(response_code: txn_id) if txn_id.present?
        unless payment.completed?
          if payment.respond_to?(:can_complete?)
            payment.complete! if payment.can_complete?
          else
            payment.complete!
          end
        end
        if order.respond_to?(:can_advance?) && order.respond_to?(:completed?)
          while !order.completed? && order.can_advance?
            begin
              order.next!
            rescue StandardError
              break
            end
          end
        else
          begin
            order.next! until order.completed?
          rescue StandardError
            # Swallow error, do not log
          end
        end
      elsif code == 'bdi6p2yy76etrs' # Pending, do not fail payment
        # leave payment as pending
      else
        payment.failure! unless payment.failed?
      end

      render plain: 'OK', status: :ok
    rescue StandardError => e
      Rails.logger.error("[iPay CALLBACK ERROR] #{e.message}")
      render plain: "Error: #{e.message}", status: :internal_server_error
    end
  end
end
