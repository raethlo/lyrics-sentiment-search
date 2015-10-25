class AddSentimentToLyrics < ActiveRecord::Migration
  def change
    add_column :lyrics, :sentiment, :string
    add_column :lyrics, :probability, :float
  end
end
