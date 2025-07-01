module Spree
  class GatewayCallbacksController < ApplicationController
    skip_before_action :verify_authenticity_token

    Rails.logger.info "[IPAY CALLBACK] GatewayCallbacksController loaded at \\#{Time.current}"

    def confirm
      Rails.logger.info "OMKUU [IPAY CALLBACK] --- CALLBACK RECEIVED ---"
      Rails.logger.info "OMKUU [IPAY CALLBACK] Time: #{Time.current}"
      Rails.logger.info "OMKUU [IPAY CALLBACK] Params: #{params.to_unsafe_h.inspect}"
      Rails.logger.info "OMKUU [IPAY CALLBACK] Session: #{session.to_hash.inspect}"
      Rails.logger.info "OMKUU [IPAY CALLBACK] Request: ip=#{request.remote_ip}, method=#{request.method}, path=#{request.fullpath}, headers=#{request.headers.env.select{|k,v| k.to_s.start_with?("HTTP_")}}"

      txn_id = params[:txnid]
      status = params[:status]
      order_number = params[:order_id] || params[:id] || params[:ivm]
      Rails.logger.info "OMKUU Using order_number='#{order_number}' (from order_id, id, or ivm param)"

      order = Spree::Order.find_by(number: order_number)
      unless order
        Rails.logger.error "OMKUU ERROR: Order not found for order_number=#{order_number} with params=#{params.to_unsafe_h.inspect}"
        render plain: "Order not found", status: :not_found
        return
      end

      payment = order.payments.last
      unless payment
        Rails.logger.error "OMKUU ERROR: Payment not found for order_number=#{order_number} (order.id=#{order.id})"
        render plain: "Payment not found", status: :not_found
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
      # OMKUU log for all
      Rails.logger.info "OMKUU IPAY CALLBACK: order_number=#{order_number}, payment id=#{payment.id}, status=#{code}, reason=#{reason}, message=#{message}, txncd=#{txncd}, msisdn_id=#{msisdn_id}, msisdn_idnum=#{msisdn_idnum}, mc=#{mc}, agt=#{agt}, card_mask=#{card_mask}, ivm=#{ivm}, id=#{id_param}"
      # State handling
      if code == 'aei7p7yrx4ae34'
        payment.update(response_code: txn_id) if txn_id.present?
        unless payment.completed?
          payment.complete!
        end
        unless order.completed?
          order.next! until order.completed?
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
      # Details table (only show Order #, Status, Message, Payer Name, Payer Phone)
      details = "<table style='margin:24px auto 0 auto;font-size:1em;text-align:left;'><tr><td style='padding:4px 12px;font-weight:bold;'>Order #:</td><td>#{order_number}</td></tr><tr><td style='padding:4px 12px;font-weight:bold;'>Status:</td><td>#{meta[:label]}</td></tr><tr><td style='padding:4px 12px;font-weight:bold;'>Message:</td><td>#{message}</td></tr><tr><td style='padding:4px 12px;font-weight:bold;'>Payer Name:</td><td>#{msisdn_id}</td></tr><tr><td style='padding:4px 12px;font-weight:bold;'>Payer Phone:</td><td>#{msisdn_idnum}</td></tr></table>"

      # Main page
      payment_path = spree.checkout_state_path(order.state)
      html = if code == 'aei7p7yrx4ae34'
        <<-HTML
<div style='max-width:600px;margin:40px auto;padding:32px;background:#e6ffe6;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,0.07);text-align:center;'>
  #{icon_svg}
  <h1 style="color:#{meta[:color]};">#{meta[:heading]}</h1>
  #{details}
  <div style="margin-top:32px;">
    <a href='#{spree.root_path}' style='display:inline-block;padding:12px 28px;background:#{meta[:color]};color:#fff;border-radius:6px;text-decoration:none;font-weight:bold;font-size:1em;'>Return to Store</a>
  </div>
</div>
        HTML
      else
        # Show two buttons: Retry Payment and Return to Store
        <<-HTML
<div style='max-width:600px;margin:40px auto;padding:32px;background:#{meta[:color]}11;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,0.07);text-align:center;'>
  #{icon_svg}
  <h1 style="color:#{meta[:color]};">#{meta[:heading]}</h1>
  <p style="margin:18px 0 0 0;font-size:1.2em;">#{message}</p>
  #{details}
  <div style="margin-top:32px;display:flex;gap:16px;justify-content:center;">
    <a href='#{payment_path}' style='display:inline-block;padding:12px 28px;background:#1976d2;color:#fff;border-radius:6px;text-decoration:none;font-weight:bold;font-size:1em;'>Retry Payment</a>
    <a href='#{spree.root_path}' style='display:inline-block;padding:12px 28px;background:#{meta[:color]};color:#fff;border-radius:6px;text-decoration:none;font-weight:bold;font-size:1em;'>Return to Store</a>
  </div>
</div>
        HTML
      end
      render html: html.html_safe, status: (code == 'aei7p7yrx4ae34' ? :ok : :payment_required)
      return

    rescue => e
      Rails.logger.error "Payment confirmation error: #{e.message}"
      render plain: "An error occurred", status: :internal_server_error
    end
  end
end
