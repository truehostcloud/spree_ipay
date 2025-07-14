# frozen_string_literal: true

class FixIpaySourcesIndexes < ActiveRecord::Migration[6.1]
  def change
    # Check if the table exists before attempting to add indexes
    return unless table_exists?(:spree_ipay_sources)

    # Add indexes if they don't already exist
    add_index :spree_ipay_sources, :payment_method_id, name: 'index_spree_ipay_sources_on_payment_method_id', if_not_exists: true
    add_index :spree_ipay_sources, :phone, name: 'index_spree_ipay_sources_on_phone', if_not_exists: true
    add_index :spree_ipay_sources, :transaction_id, name: 'index_spree_ipay_sources_on_transaction_id', unique: true, if_not_exists: true
    add_index :spree_ipay_sources, :status, name: 'index_spree_ipay_sources_on_status', if_not_exists: true
  end
end
