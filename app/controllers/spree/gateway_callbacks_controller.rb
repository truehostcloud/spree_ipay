module Spree
  # Handles callbacks from the iPay payment gateway.
  # Processes payment confirmations and updates order statuses based on iPay responses.
  # This controller skips CSRF protection for the confirm action to allow external callbacks.
  class GatewayCallbacksController < ApplicationController
    layout false # Don't use the application layout
    skip_before_action :verify_authenticity_token, only: [:confirm]

    def confirm
      txn_id = params[:txnid]
      status = params[:status]
      order_number = params[:order_id] || params[:id] || params[:ivm]

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
        Rails.logger.warn "iPay Callback: Amount paid (#{paid_amount}) is less than order total (#{required_amount}) for order #{order.number}"
        render plain: "Amount paid (#{paid_amount}) is less than required (#{required_amount})",
               status: :payment_required
        return
      end

      # iPay status code handling (see docs)
      status_map = {
        'aei7p7yrx4ae34' => { label: 'Success', color: '#3bb143', icon: 'success',
                              heading: 'Order Placed Successfully!' },
        'fe2707etr5s4wq' => { label: 'Failed', color: '#d32f2f', icon: 'fail', heading: 'Payment Failed' },
        'bdi6p2yy76etrs' => { label: 'Pending', color: '#fbc02d', icon: 'pending', heading: 'Payment Pending' },
        'cr5i3pgy9867e1' => { label: 'Used', color: '#d32f2f', icon: 'fail', heading: 'Code Already Used' },
        'dtfi4p7yty45wq' => { label: 'Less', color: '#d32f2f', icon: 'fail', heading: 'Insufficient Payment' },
        'eq3i7p5yt7645e' => { label: 'More', color: '#1976d2', icon: 'info', heading: 'Overpayment' }
      }
      code = status.to_s
      meta = status_map[code] || { label: 'Unknown', color: '#d32f2f', icon: 'fail', heading: 'Payment Failed' }
      params[:reasonCode] || meta[:label]
      message = params[:message] || 'There was an issue processing your payment.'
      params[:txncd] || ''
      msisdn_id = params[:msisdn_id] || ''
      msisdn_idnum = params[:msisdn_idnum] || ''
      params[:mc] || ''
      params[:agt] || ''
      params[:card_mask] || ''
      params[:ivm] || ''
      params[:id] || ''
      params[:p1] || ''
      params[:p2] || ''
      params[:p3] || ''
      params[:p4] || ''
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
      # Icon SVGs
      case meta[:icon]
      when 'success' then '<svg width="64" height="64" fill="none" viewBox="0 0 24 24" style="margin-bottom:24px;"><circle cx="12" cy="12" r="10" fill="#e6ffe6"/><path d="M8.5 12.5l2.5 2.5 4.5-4.5" stroke="#3bb143" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
      when 'pending' then '<svg width="64" height="64" fill="none" viewBox="0 0 24 24" style="margin-bottom:24px;"><circle cx="12" cy="12" r="10" fill="#fffbe6"/><path d="M12 8v4l3 3" stroke="#fbc02d" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
      else '<svg width="64" height="64" fill="none" viewBox="0 0 24 24" style="margin-bottom:24px;"><circle cx="12" cy="12" r="10" fill="#ffe6e6"/><path d="M8 12l4 4 4-8" stroke="#d32f2f" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
      end

      # Escape all dynamic/user variables
      esc_order_number = ERB::Util.html_escape(order.number)
      esc_status = ERB::Util.html_escape(meta[:label])
      esc_message = ERB::Util.html_escape(message)
      esc_payer_name = ERB::Util.html_escape(msisdn_id)
      esc_payer_phone = ERB::Util.html_escape(msisdn_idnum)
      esc_heading = ERB::Util.html_escape(meta[:heading])
      esc_color = ERB::Util.html_escape(meta[:color]) # assumed safe, as it's generated SVG markup
      esc_root_path = ERB::Util.html_escape(spree.root_path)
      esc_payment_path = ERB::Util.html_escape(spree.checkout_state_path(order.state))

      # Build details table safely using helpers
      @details = helpers.content_tag(:table,
                                     helpers.safe_join([
                                                         helpers.content_tag(:tr,
                                                                             helpers.content_tag(:th, 'Order #:',
                                                                                                 style: 'padding:4px 12px;font-weight:bold;text-align:left;') +
                                                                             helpers.content_tag(:td,
                                                                                                 esc_order_number)),
                                                         helpers.content_tag(:tr,
                                                                             helpers.content_tag(:th, 'Status:',
                                                                                                 style: 'padding:4px 12px;font-weight:bold;text-align:left;') +
                                                                             helpers.content_tag(:td, esc_status)),
                                                         helpers.content_tag(:tr,
                                                                             helpers.content_tag(:th, 'Message:',
                                                                                                 style: 'padding:4px 12px;font-weight:bold;text-align:left;') +
                                                                             helpers.content_tag(:td, esc_message)),
                                                         helpers.content_tag(:tr,
                                                                             helpers.content_tag(:th, 'Payer Name:',
                                                                                                 style: 'padding:4px 12px;font-weight:bold;text-align:left;') +
                                                                             helpers.content_tag(:td, esc_payer_name)),
                                                         helpers.content_tag(:tr,
                                                                             helpers.content_tag(:th, 'Payer Phone:',
                                                                                                 style: 'padding:4px 12px;font-weight:bold;text-align:left;') +
                                                                             helpers.content_tag(:td, esc_payer_phone))
                                                       ]),
                                     style: 'margin:24px auto 0 auto;font-size:1em;text-align:left;border-collapse:collapse;width:100%;max-width:600px;')

      # Set template variables
      @color = esc_color
      @icon = meta[:icon]
      @heading = esc_heading
      @root_path = esc_root_path

      if code == 'aei7p7yrx4ae34'
        # Show success page
        render 'success', status: :ok
      else
        # Show failure page with retry option
        @message = esc_message
        @payment_path = esc_payment_path
        render 'failure', status: :payment_required
      end
    rescue StandardError => e
      # Prepare error metadata
      @meta = {
        heading: 'Error Processing Payment',
        message: 'An error occurred while processing your payment. Please try again or contact support.',
        color: '#d32f2f',
        icon: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z',
        error: e.message,
        root_path: spree.root_path
      }

      # Set instance variables for the view
      @heading = @meta[:heading]
      @message = @meta[:message]
      @color = @meta[:color]
      @icon = @meta[:icon]
      @error = @meta[:error]
      @root_path = @meta[:root_path]

      # Render the error template
      render 'error', status: :internal_server_error
    end
  end
end
