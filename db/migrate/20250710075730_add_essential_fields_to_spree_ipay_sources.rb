class AddEssentialFieldsToSpreeIpaySources < ActiveRecord::Migration[7.1]
  def up
    # Check if the table exists
    table_exists = table_exists?(:spree_ipay_sources)
    
    if table_exists
      # Table exists, just add the new columns if they don't exist
      add_column_if_not_exists :spree_ipay_sources, :status, :string, default: 'pending'
      add_column_if_not_exists :spree_ipay_sources, :transaction_id, :string
      add_column_if_not_exists :spree_ipay_sources, :transaction_reference, :string
      add_column_if_not_exists :spree_ipay_sources, :transaction_amount, :decimal, precision: 10, scale: 2
      add_column_if_not_exists :spree_ipay_sources, :transaction_timestamp, :datetime
      add_column_if_not_exists :spree_ipay_sources, :metadata, :jsonb, default: {}
      
      # Add indexes if they don't exist
      add_index :spree_ipay_sources, :status, name: 'index_spree_ipay_sources_on_status', if_not_exists: true
      add_index :spree_ipay_sources, :transaction_id, unique: true, name: 'index_spree_ipay_sources_on_transaction_id', if_not_exists: true
    else
      # Table doesn't exist, create it with all fields
      create_table :spree_ipay_sources, force: :cascade do |t|
        t.string :phone, null: false
        t.references :payment_method, null: false, foreign_key: { to_table: :spree_payment_methods }
        
        # Transaction details
        t.string :status, default: 'pending'
        t.string :transaction_id
        t.string :transaction_reference
        t.decimal :transaction_amount, precision: 10, scale: 2
        t.datetime :transaction_timestamp
        t.jsonb :metadata, default: {}
        
        t.timestamps
        
        t.index [:payment_method_id], name: 'index_spree_ipay_sources_on_payment_method_id'
        t.index :status, name: 'index_spree_ipay_sources_on_status'
        t.index :transaction_id, unique: true, name: 'index_spree_ipay_sources_on_transaction_id'
      end
    end
  end
  
  def down
    # Only drop the table if it was created by this migration
    unless table_exists?(:spree_ipay_sources, :before_migration)
      drop_table :spree_ipay_sources
    else
      # Otherwise, just remove the columns that were added
      remove_column :spree_ipay_sources, :status, if_exists: true
      remove_column :spree_ipay_sources, :transaction_id, if_exists: true
      remove_column :spree_ipay_sources, :transaction_reference, if_exists: true
      remove_column :spree_ipay_sources, :transaction_amount, if_exists: true
      remove_column :spree_ipay_sources, :transaction_timestamp, if_exists: true
      remove_column :spree_ipay_sources, :metadata, if_exists: true
      
      # Remove indexes
      remove_index :spree_ipay_sources, name: 'index_spree_ipay_sources_on_status', if_exists: true
      remove_index :spree_ipay_sources, name: 'index_spree_ipay_sources_on_transaction_id', if_exists: true
    end
  end
  
  private
  
  # Helper method to safely add a column if it doesn't exist
  def add_column_if_not_exists(table, column, type, **options)
    return if column_exists?(table, column)
    add_column(table, column, type, **options)
  end
  
  # Helper to check if table existed before migration
  def table_existed_before_migration?(table_name)
    # This is a simplified check - in a real scenario, you might want to track this in a separate table
    # or use a more sophisticated method to determine if the table existed before
    @tables_before ||= {}
    @tables_before[table_name] ||= table_exists?(table_name)
  end
end