class AddUserReferenceToIpaySources < ActiveRecord::Migration[6.1]
  def change
    add_reference :spree_ipay_sources, :user, foreign_key: { to_table: :spree_users }, index: true
  end
end
