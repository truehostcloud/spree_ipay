# frozen_string_literal: true

class AddIndexesForIpayPerformance < ActiveRecord::Migration[6.1]
  def change
    add_index :spree_ipay_sources, :order_id
    add_index :spree_ipay_sources, :payment_method_id
    add_index :spree_ipay_sources, :phone_number
    add_index :spree_ipay_sources, :transaction_id
    add_index :spree_ipay_sources, :status
  end
end
