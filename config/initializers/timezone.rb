geonames_username = Rails.application.credentials.dig(:geonames, :username)

if geonames_username.present?
  Timezone::Lookup.config(:geonames) do |c|
    c.username = geonames_username
    c.offset_etc_zones = true
  end
end
