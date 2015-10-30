# Fast In-Memory Search
```
    Autor: Roman Roštár 
    Predmet: Vyhľadávanie Informácií
    Rok: 2015/16
```
## Zadanie
V rámci prvého zadania bolo cieľom získať dostatočne veľkú množinu nie trivialnych dát, a nad nimi následne vytvoriť in-memory search a demonštrovať dopyty nad daným search enginom.

Ako doménu môjho zadania som si zvolil texty pesničiek. Teda bolo najprv nutné nájsť stránky, kde môžem texty pesničiek strojovým spracovaním získať, tieto stránky scrapovať, získané dáta očistiť a nakoniec nad nimi vytvoriť  vyhľadávateľný reverzný index, pričom texty pesničiek som ešte obohatil o sentiment.

Na implementáciu in-memory vyhľadávania som sa rozhodol použiť elasticsearch. Zvyšné skripty som implementoval v ruby.

## Dáta
Stránok poskytujúcich texty pesničiek je pomerne veľa, výzvou však bolo ich strojové spracovanie. Väčšina stránok z top hitov google query “lyrics” ako neposkytujú RESTful url štruktúru, čiže veľmi neprichádza do úvahy ich scrapovať podľa id dokumentu. Napríklad pri stránke AZlyrics url štruktúra vyzerá následovne.

* pre autora - http://www.azlyrics.com/r/radiohead.html
* pre pesničku - http://www.azlyrics.com/lyrics/radiohead/stopwhispering.html

Takáto štruktúra stránky by sa dala spracúvať buď spiderom, ktorý by klikal na odkazy mien autorov, následne pesničiek a potom ich scrapoval, alebo nejakým spôsobom by bolo nutné lepiť názvy pesničiek a interpretov do url, pričom väčšina zo stránok, ktoré som našiel mala takúto štruktúru.

Stránka www.songmeanings.com sa však dala scrapovať podľa id, url textu jednotlivých pesničiek bola daná http://songmeanings.com/songs/view/1/. Teda sa dalo jednoduchšie iterovať cez id dokumentov a zo stránok parsovať texty pesničiek.
## Scraper
Scraper som implementoval v ruby, pričom som využil sidekiq ako job queue, do ktorej som vkladal scrapovacie úlohy podľa id dokumentu. Ako parsovaciu knižnicu som použil [nokogiri](http://www.nokogiri.org/)
```ruby
require 'faraday'
require 'nokogiri'

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
```

Tuto logiku som obalil do sidekiq jobu a jednotlive záznamy ukladal (dočasne) do databázy. Dáta som ukladal ako jednu entitu, ktorá obsahovala záznam o umelcovi, albume, mene piesne a a nakoniec textu piesne.

```ruby
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
      lyric = Lyric.new(sm_id: song_id.to_s, artist: artist, album: album, song: song, text: lyrics)
      lyric.save!
    end
  end

  def scrape(id)
    page = open_song_page(id)
    scrape_lyric(page)
  end
end
```
Pri scrapovaní som narazil na pár problémov, s ktorými som pri implementácii nerátal. Songmeanings totiž pri nenájdení záznamu pod nejakým id nevrátilo HTTP status 404 ale vyrenderovalo stránku, ktorá pod css selectorom,kde býva text používateľovi oznamovala, že taký text neexistuje. Taktiež niektoré piesne na mieste, kde  mal byť text mala oznam, že daný text chýba.

Dokopy som scrapoval 3.5 milióna stránok, z čoho bolo dokopy validných iba niečo viac ako 500 000 záznamov. Po očistení vyššie spomenutých chybných záznamov ostalo približne 450 000 záznamov.

Záznamy som rozšíril o dve polia, teda sentiment a probability (pravdepodobnosť s akou istotou je extrahovaný sentiment správny). Pre určovanie sentimentu textov som použili gem [sentimentalizer](https://github.com/malavbhavsar/sentimentalizer) a texty sme pomocou rake tasku obohatili o sentiment.
```
 desc('analyze all songs')
  task(analyze: :environment) do
    Sentimentalizer.setup

    Lyric.where(sentiment: nil).each do |lyric|
      begin
        result = Sentimentalizer.analyze(lyric.text.strip)

        case result.sentiment
          when ':('
            sentiment = 'negative'
          when ':)'
            sentiment = 'positive'
          when ':|'
            sentiment = 'neutral'
          else
            sentiment = 'undefined'
        end

        lyric.sentiment = sentiment
        lyric.probability = result.overall_probability

        puts "#{lyric.artist}  - #{lyric.song} is #{lyric.sentiment} for #{lyric.probability}"

        lyric.save!
      rescue => e
        puts e.message
        puts e.backtrace
      end
    end
  end
```
Sentimentový preprocessing bol časovo veľmi náročný, zhruba 10 sekúnd na jeden záznam, čiže z konečných 440 000 záznamov sme sentimentom ohodnotili iba vzorku 10 000 dokumentov.

## In memory search
Získané dokumenty som vytiahol vo forme veľkých json objektov obsahujúcich tisíce záznamov a importoval do elasticsearchu pomocou bulk-index API. Najprv som využil vlastnosť elasticsearchu, že pri post/put requeste na ešte nevztvorený index vytvorí index implicitne podľa prvého záznamu problém, však nastal pri requeste typu:
```json
GET /sentimental/lyric/_search
{
  "query": {
    "filtered": {
      "query": {
        "match": {
          "artist": "Joe Cocker"
        }
      }
    }
  }
}
```
Kde vrátil aj záznamy, ako napríklad tie, čo obsahovali "Joe". Tento problém som vyriešil vytvorením multi-field mappingu.

```json
PUT /sentimental
{
  "mappings": {
    "lyric": {
      "properties": {
        "artist": {
          "type": "multi_field",
          "fields": {
            "artist": {
              "type": "string",
              "index": "analyzed"
            },
            "untouched": {
              "type": "string",
              "index": "analyzed",
              "analyzer": "keyword"
            }
          }
        },
        "album": {
          "type": "string"
        },
        "song": {
          "type": "string"
        },
        "text": {
          "type": "string"
        },
        "sentiment": {
          "type": "string",
          "analyzer": "keyword"
        },
        "probability": {
          "type": "float"
        }
      }
    }
  }
}
```

Kde artist je indexovaný dvomi analyzermi, a to štandardným a token analyzerom pod fieldom "artist.untouched". A teda uvedena query vratila len tie s presne uvedeným názvom interpreta. (dalo sa to vyriešiť query "match_phrase").

## Queries
Najdi všetky záznamy "Joe Cocker"-a, ktoré majú sentiment.
```json
GET /sentimental/lyric/_search
{
  "query": {
    "filtered": {
      "query": {
        "match": {
          "artist.untouched": "Joe Cocker"
        }
      },
      "filter": {
        "exists": {
          "field": "sentiment"
        }
      }
    }
  }
}
```

Nájdi všetky záznamy, ktoré sú textom podobné konkrétnemu inému textu.
```json
GET /sentimental/lyric/_search
{
  "query": {
    "more_like_this": {
      "fields": [
        "text"
      ],
      "ids": [358],
      "min_term_freq": 1,
      "max_query_terms": 12
    }
  }
}
```

Nájdi texty, ktoré sú podobné ako texty Joe Cocker-a 
```json
GET /sentimental/lyric/_search
{
  "query": {
    "filtered": {
      "query": {
        "more_like_this": {
          "fields": [
            "text"
          ],
          "docs": [
            {
              "_index": "sentimental",
              "_type": "lyric",
              "doc": {
                "artist.untouched": "Joe Cocker"
              }
            }
          ],
          "min_term_freq": 1,
          "max_query_terms": 12
        }
      },
      "filter": {
        "bool": {
          "must_not": [
            {
              "term": {
                "artist.untouched": "Joe Cocker"
              }
            }
          ]
        }
      }
    }
  }
}
```

Spočítaj počty kategórií sentimentu. (negative, positive, neutral)
```json
GET /sentimental/lyric/_search
{
  "query": {
    "match_all": {}
  },
  "aggs": {
    "sentiment_count": {
      "terms": {
        "field": "sentiment"
      }
    }
  }
}
```