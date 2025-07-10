class CompleteIpaySourcesTable < ActiveRecord::Migration[6.1]
  def change
    # Remove any existing columns that might be causing conflicts
    remove_column :spree_ipay_sources, :user_id, :integer, if: column_exists?(:spree_ipay_sources, :user_id)
    
    # Add all required columns
    add_reference :spree_ipay_sources, :user, foreign_key: { to_table: :spree_users }, index: true
    
    add_column :spree_ipay_sources, :status, :string, default: 'pending'
    add_column :spree_ipay_sources, :transaction_id, :string
    add_column :spree_ipay_sources, :transaction_code, :string
    add_column :spree_ipay_sources, :transaction_reference, :string
    add_column :spree_ipay_sources, :transaction_amount, :decimal, precision: 10, scale: 2
    add_column :spree_ipay_sources, :transaction_currency, :string
    add_column :spree_ipay_sources, :transaction_timestamp, :datetime
    add_column :spree_ipay_sources, :metadata, :jsonb, default: {}
    
    # Add indexes
    add_index :spree_ipay_sources, :status
    add_index :spree_ipay_sources, :transaction_id, unique: true
  end
end
