module Spree
  class GatewayCallbacksController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:confirm]

    def confirm
      # Log all callback parameters to the terminal using Omkuu
      if defined?(Omkuu)
        Omkuu.log(:info, "iPay Callback Params: #{params.to_unsafe_h.inspect}")
      else
        Rails.logger.info "[OMKUU] iPay Callback Params: #{params.to_unsafe_h.inspect}"
      end

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
        if defined?(Omkuu)
          Omkuu.log(:warn, "iPay Callback: Amount paid (#{paid_amount}) is less than order total (#{required_amount}) for order #{order.number}")
        else
          Rails.logger.warn "[OMKUU] iPay Callback: Amount paid (#{paid_amount}) is less than order total (#{required_amount}) for order #{order.number}"
        end
        render plain: "Amount paid (#{paid_amount}) is less than required (#{required_amount})", status: :payment_required
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
      reason = params[:reasonCode] || meta[:label]
      message = params[:message] || 'There was an issue processing your payment.'
      txncd = params[:txncd] || ''
      msisdn_id = params[:msisdn_id] || ''
      msisdn_idnum = params[:msisdn_idnum] || ''
      mc = params[:mc] || ''
      agt = params[:agt] || ''
      card_mask = params[:card_mask] || ''
      ivm = params[:ivm] || ''
      id_param = params[:id] || ''
      p1 = params[:p1] || ''
      p2 = params[:p2] || ''
      p3 = params[:p3] || ''
      p4 = params[:p4] || ''
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
            rescue => e
              break
            end
          end
        else
          begin
            order.next! until order.completed?
          rescue => e
            # Swallow error, do not log
          end
        end
      elsif code == 'bdi6p2yy76etrs' # Pending, do not fail payment
        # leave payment as pending
      else
        unless payment.failed?
          payment.failure!
        end
      end
      # Icon SVGs
      icon_svg = case meta[:icon]
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
      esc_color = ERB::Util.html_escape(meta[:color])
      esc_icon_svg = icon_svg # assumed safe, as it's generated SVG markup
      esc_root_path = ERB::Util.html_escape(spree.root_path)
      esc_payment_path = ERB::Util.html_escape(spree.checkout_state_path(order.state))

      # Details table (only show Order #, Status, Message, Payer Name, Payer Phone)
      details = "<table style='margin:24px auto 0 auto;font-size:1em;text-align:left;'><tr><td style='padding:4px 12px;font-weight:bold;'>Order #:</td><td>#{esc_order_number}</td></tr><tr><td style='padding:4px 12px;font-weight:bold;'>Status:</td><td>#{esc_status}</td></tr><tr><td style='padding:4px 12px;font-weight:bold;'>Message:</td><td>#{esc_message}</td></tr><tr><td style='padding:4px 12px;font-weight:bold;'>Payer Name:</td><td>#{esc_payer_name}</td></tr><tr><td style='padding:4px 12px;font-weight:bold;'>Payer Phone:</td><td>#{esc_payer_phone}</td></tr></table>"

      if code == 'aei7p7yrx4ae34'
        # Show success page
        html = <<~HTML
          <div style='max-width:600px;margin:40px auto;padding:32px;background:#{esc_color}11;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,0.07);text-align:center;'>
            #{esc_icon_svg}
            <h1 style="color:#{esc_color};">#{esc_heading}</h1>
            #{details}
            <div style="margin-top:32px;">
              <a href='#{esc_root_path}' style='display:inline-block;padding:12px 28px;background:#{esc_color};color:#fff;border-radius:6px;text-decoration:none;font-weight:bold;font-size:1em;'>Return to Store</a>
            </div>
          </div>
        HTML
      else
        # Show two buttons: Retry Payment and Return to Store
        html = <<~HTML
          <div style='max-width:600px;margin:40px auto;padding:32px;background:#{esc_color}11;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,0.07);text-align:center;'>
            #{esc_icon_svg}
            <h1 style="color:#{esc_color};">#{esc_heading}</h1>
            <p style="margin:18px 0 0 0;font-size:1.2em;">#{esc_message}</p>
            #{details}
            <div style="margin-top:32px;display:flex;gap:16px;justify-content:center;">
              <a href='#{esc_payment_path}' style='display:inline-block;padding:12px 28px;background:#1976d2;color:#fff;border-radius:6px;text-decoration:none;font-weight:bold;font-size:1em;'>Retry Payment</a>
              <a href='#{esc_root_path}' style='display:inline-block;padding:12px 28px;background:#{esc_color};color:#fff;border-radius:6px;text-decoration:none;font-weight:bold;font-size:1em;'>Return to Store</a>
            </div>
          </div>
        HTML
      end
      render html: html.html_safe, status: (code == 'aei7p7yrx4ae34' ? :ok : :payment_required)
      return
    rescue => e
      render plain: "An error occurred", status: :internal_server_error
    end
  end
end
