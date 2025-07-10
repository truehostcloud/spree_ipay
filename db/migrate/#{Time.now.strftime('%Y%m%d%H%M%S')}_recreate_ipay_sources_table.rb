class RecreateIpaySourcesTable < ActiveRecord::Migration[6.1]
  def up
    # Drop the existing table if it exists
    drop_table :spree_ipay_sources, if_exists: true

    # Create the table with all required columns
    create_table :spree_ipay_sources do |t|
      t.references :payment_method, foreign_key: { to_table: :spree_payment_methods }, index: true
      t.references :user, foreign_key: { to_table: :spree_users }, index: true
      
      t.string :phone, null: false
      t.string :status, default: 'pending'
      t.string :transaction_id
      t.string :transaction_code
      t.string :transaction_reference
      t.decimal :transaction_amount, precision: 10, scale: 2
      t.string :transaction_currency
      t.datetime :transaction_timestamp
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    # Add indexes
    add_index :spree_ipay_sources, :status
    add_index :spree_ipay_sources, :transaction_id, unique: true
  end

  def down
    drop_table :spree_ipay_sources
  end
end
