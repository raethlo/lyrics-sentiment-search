class LyricImport
  def self.import
    Lyric.find_in_batches do |lyrics|
      bulk_index(lyrics)
    end
  end

  def self.prepare_records(lyrics)
    lyrics.map do |lyric|
      { index: { _id: lyric.id, data: lyric.as_indexed_json } }
    end
  end

  def self.bulk_index(lyrics)
    client = Elasticsearch::Client.new log: true
    client.transport.reload_connections!

    client.bulk index: 'test', type: 'lyric', body: prepare_records(lyrics)
  end
end