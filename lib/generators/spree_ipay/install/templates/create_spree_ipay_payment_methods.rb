# frozen_string_literal: true

class CreateSpreeIpayPaymentMethods < ActiveRecord::Migration[7.1]
  def up
    # Add iPay specific fields to spree_payment_methods if they don't exist
    unless column_exists?(:spree_payment_methods, :vendor_id)
      add_column :spree_payment_methods, :vendor_id, :string
    end
    
    unless column_exists?(:spree_payment_methods, :hash_key)
      add_column :spree_payment_methods, :hash_key, :string
    end
    
    unless column_exists?(:spree_payment_methods, :test_mode)
      add_column :spree_payment_methods, :test_mode, :boolean, default: true
    end
  end

  def down
    remove_column :spree_payment_methods, :vendor_id if column_exists?(:spree_payment_methods, :vendor_id)
    remove_column :spree_payment_methods, :hash_key if column_exists?(:spree_payment_methods, :hash_key)
    remove_column :spree_payment_methods, :test_mode if column_exists?(:spree_payment_methods, :test_mode)
  end
end