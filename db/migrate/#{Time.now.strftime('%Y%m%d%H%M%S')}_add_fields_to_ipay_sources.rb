class AddFieldsToIpaySources < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_ipay_sources, :phone, :string
    add_column :spree_ipay_sources, :status, :string, default: 'pending'
    add_column :spree_ipay_sources, :transaction_id, :string
    add_column :spree_ipay_sources, :transaction_code, :string
    add_column :spree_ipay_sources, :transaction_reference, :string
    add_column :spree_ipay_sources, :transaction_amount, :decimal, precision: 10, scale: 2
    add_column :spree_ipay_sources, :transaction_currency, :string
    add_column :spree_ipay_sources, :transaction_timestamp, :datetime
    add_column :spree_ipay_sources, :metadata, :jsonb, default: {}
    
    add_index :spree_ipay_sources, :transaction_id
    add_index :spree_ipay_sources, :status
  end
end
