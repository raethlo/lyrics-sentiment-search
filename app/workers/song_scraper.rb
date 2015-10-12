require 'faraday'
require 'nokogiri'

class SongScraper
  include Sidekiq::Worker

  def perform(song_id)
    data = scrape(song_id)
    if data.blank?
      Rails.logger.error "Lyrics for given id: #{song_id} dont exist"
      return
    end

    artist, album, song, lyrics = data.values

    if Lyric.where(artist: artist, song: song).any?
      Rails.logger.error "data for #{artist} - #{song} exists, laterz"
    else
      lyric = Lyric.new(artist: artist, album: album, song: song, text: lyrics)
      lyric.save!
    end
  end

  def scrape(id)
    page = open_song_page(id)
    scrape_lyric(page)
  end

  private
    def open_song_page(id)
      url = "http://songmeanings.com/songs/view/#{id}"

      html =  Faraday.get url
      doc = Nokogiri.HTML html.body
    end

    def scrape_lyric(doc)
      return nil if doc.css('#headerstatus').any?

      bread = doc.css('ul.breadcrumbs')
      navigation = bread.css('li')

      _, artist, album, song = navigation.map { |li| li.text.strip }

      lyrics_box = doc.css('div.lyric-box')
      lyrics_box.children.css('div').remove

      lyrics = lyrics_box.text

      {
          artist: artist,
          album: album,
          song: song,
          lyrics: lyrics
      }
    end
end
