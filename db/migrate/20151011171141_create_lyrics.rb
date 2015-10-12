class CreateLyrics < ActiveRecord::Migration
  def change
    create_table :lyrics do |t|
      t.string :artist
      t.string :album
      t.string :song
      t.string :text

      t.timestamps null: false
    end
  end
end
