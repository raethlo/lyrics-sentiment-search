require 'sentimentalizer'

namespace :sentiment do

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
end
