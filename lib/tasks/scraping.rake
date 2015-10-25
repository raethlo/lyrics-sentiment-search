namespace :scraping do

  desc('spawn crawlers')
  task(spawn: :environment) do
    howmany = 200000
    top = 3530822107858674644
    i = top + howmany + howmany + homwany

    howmany.times do
      SongScraper.perform_async(i)

      i += 1
    end
  end
end
