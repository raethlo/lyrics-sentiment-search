class Lyric < ActiveRecord::Base
  def as_indexed_json
    artist_keyword =

    self.as_json only: [:artist, :album, :song, :text, :sentiment, :probability]
  end
end