class Lyric < ActiveRecord::Base
  def as_indexed_json
    self.as_json only: [:artist, :album, :song, :text, :sentiment, :probability]
  end
end
