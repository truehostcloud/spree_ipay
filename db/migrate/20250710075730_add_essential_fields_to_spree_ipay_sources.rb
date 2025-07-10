class AddEssentialFieldsToSpreeIpaySources < ActiveRecord::Migration[7.1]
  def up
    # Check if the table exists
    table_exists = table_exists?(:spree_ipay_sources)
    
    if table_exists
      # Table exists, just add the new columns if they don't exist
      add_column_if_not_exists :spree_ipay_sources, :phone, :string
      add_column_if_not_exists :spree_ipay_sources, :payment_method_id, :integer

      # Update existing records with appropriate values before adding constraints
      # change_column_null :spree_ipay_sources, :phone, false after updating records
      # change_column_null :spree_ipay_sources, :payment_method_id, false after updating records
      add_column_if_not_exists :spree_ipay_sources, :status, :string, default: 'pending'
      add_column_if_not_exists :spree_ipay_sources, :transaction_id, :string, limit: 191
      add_column_if_not_exists :spree_ipay_sources, :transaction_reference, :string
      add_column_if_not_exists :spree_ipay_sources, :transaction_amount, :decimal, precision: 10, scale: 2
      add_column_if_not_exists :spree_ipay_sources, :transaction_timestamp, :datetime
      
      # Add metadata with conditional type
      if metadata_column_type == :jsonb
        add_column_if_not_exists :spree_ipay_sources, :metadata, :jsonb, default: {}
      else
        # MySQL doesn't support default values for JSON columns
        add_column_if_not_exists :spree_ipay_sources, :metadata, :json
      end
      
      # Add foreign key constraint if it doesn't exist
      unless foreign_key_exists?(:spree_ipay_sources, :spree_payment_methods)
        add_foreign_key :spree_ipay_sources, :spree_payment_methods, column: :payment_method_id
      end
      
      # Add indexes if they don't exist
      add_index :spree_ipay_sources, :payment_method_id, name: 'index_spree_ipay_sources_on_payment_method_id', if_not_exists: true
      add_index :spree_ipay_sources, :status, name: 'index_spree_ipay_sources_on_status', if_not_exists: true
      add_index :spree_ipay_sources, :transaction_id, unique: true, name: 'index_spree_ipay_sources_on_transaction_id', length: 191, if_not_exists: true
    else
      # Table doesn't exist, create it with all fields
      create_table :spree_ipay_sources, force: :cascade do |t|
        t.string :phone, null: false
        t.references :payment_method, null: false, foreign_key: { to_table: :spree_payment_methods }, index: { name: 'index_spree_ipay_sources_on_payment_method_id' }
        
        # Transaction details
        t.string :status, default: 'pending'
        t.string :transaction_id, limit: 191
        t.string :transaction_reference
        t.decimal :transaction_amount, precision: 10, scale: 2
        t.datetime :transaction_timestamp
        
        # Use the appropriate JSON type based on the database
        if t.respond_to?(:jsonb)
          t.jsonb :metadata, default: {}
        else
          # MySQL doesn't support default values for JSON columns
          t.json :metadata
        end
        
        t.timestamps
        
        t.index :status, name: 'index_spree_ipay_sources_on_status'
        t.index :transaction_id, unique: true, name: 'index_spree_ipay_sources_on_transaction_id', length: 191
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
      
      # Only remove the foreign key if it exists
      if foreign_key_exists?(:spree_ipay_sources, :spree_payment_methods)
        remove_foreign_key :spree_ipay_sources, column: :payment_method_id
      end
      
      # Only remove the payment_method_id column if it exists
      if column_exists?(:spree_ipay_sources, :payment_method_id)
        remove_column :spree_ipay_sources, :payment_method_id
      end

      # Only remove the phone column if it exists
      if column_exists?(:spree_ipay_sources, :phone)
        remove_column :spree_ipay_sources, :phone
      end
      
      # Remove indexes if they exist
      remove_index :spree_ipay_sources, name: 'index_spree_ipay_sources_on_payment_method_id', if_exists: true
      remove_index :spree_ipay_sources, name: 'index_spree_ipay_sources_on_status', if_exists: true
      remove_index :spree_ipay_sources, name: 'index_spree_ipay_sources_on_transaction_id', if_exists: true
    end
  end
  
  private
  
  # Helper method to safely add columns only if they don't exist
  def add_column_if_not_exists(table, column, type, **options)
    return if column_exists?(table, column)
    add_column(table, column, type, **options)
  end
  
  # Determine the appropriate JSON column type for the databae
  def metadata_column_type
    @metadata_column_type ||= begin
      if ActiveRecord::Base.connection.adapter_name.downcase.include?('postgresql')
        :jsonb
      else
        :json
      end
    end
  end
end