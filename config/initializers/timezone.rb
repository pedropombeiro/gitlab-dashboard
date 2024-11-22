Timezone::Lookup.config(:geonames) do |c|
  c.username = ENV["GEONAMES_USERNAME"]
end if ENV["GEONAMES_USERNAME"].present?
