class CreateSpreeIpaySources < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_ipay_sources do |t|
      t.string :phone, null: false
      t.references :payment_method, null: false, foreign_key: { to_table: :spree_payment_methods }

      t.timestamps
    end
  end
end
