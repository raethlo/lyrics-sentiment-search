class AddSmIdToLyrics < ActiveRecord::Migration
  def change
    add_column :lyrics, :sm_id, :string, null: true
  end
end
