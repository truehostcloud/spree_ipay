class AddUserIdToSpreeIpaySources < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:spree_ipay_sources, :user_id)

    add_reference :spree_ipay_sources,
                  :user,
                  foreign_key: { to_table: spree_user_table_name },
                  index: true,
                  null: true
  end

  private

  def spree_user_table_name
    Spree.user_class.table_name
  end
end