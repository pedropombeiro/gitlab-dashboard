if ENV["GEONAMES_USERNAME"].present?
  Timezone::Lookup.config(:geonames) do |c|
    c.username = ENV["GEONAMES_USERNAME"]
  end
end
