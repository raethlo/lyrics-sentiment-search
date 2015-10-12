namespace :scraping do

  desc('spawn crawlers')
  task(spawn: :environment) do
    i = 260000
    wut = 2000000 - i

    wut.times do
      # puts i
      SongScraper.perform_async(i)

      i += 1
    end
  end
end
