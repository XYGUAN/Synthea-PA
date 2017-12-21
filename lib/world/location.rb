module Synthea
  class Location
    @geom = GeoRuby::SimpleFeatures::Geometry.from_geojson(Synthea::MA_geo)
    @running_total = 0
    @geom.features.each do |feat|
      @running_total += feat.properties['pop']
    end
    @city_zipcode_hash = JSON.parse(File.read(File.expand_path('city_zip.json', File.dirname(File.absolute_path(__FILE__)))))
    @town_list = JSON.parse(File.read(File.join(File.dirname(__FILE__), '..', '..', 'config', 'towns.json')))

    def self.get_zipcode(city, state = 'MA')
      return 'XXXXX' unless city
      zipcode_list = @city_zipcode_hash[city] || @city_zipcode_hash[city + ' Town']
      if zipcode_list && state == 'MA'
        zipcode_list.sample
      else
        'XXXXX'
      end
    end

    def self.select_town
      city = @town_list.keys.sample
      state = @town_list[city]['state']
      { city: city, state: state }
    end

    def self.select_point(city_name, state = 'MA')
      feat_index = find_index_of_city(city_name) if state == 'MA'

      return nil unless feat_index

      # determine rough boundaries of city
      city = @geom.features[feat_index].geometry.geometries[0]
      max_y = -999
      max_x = -999
      min_y = 999
      min_x = 999
      city.rings[0].points.each do |point|
        max_x = point.x if point.x > max_x
        max_y = point.y if point.y > max_y
        min_x = point.x if point.x < min_x
        min_y = point.y if point.y < min_y
      end

      # randomly pick points within boundaries until one falls within city borders and return
      loop do
        x = rand(min_x..max_x)
        y = rand(min_y..max_y)
        point = GeoRuby::SimpleFeatures::Point.from_x_y(x, y)
        return { 'point' => point, 'city' => city_name } if city.contains_point?(point)
      end
    end

    def self.find_index_of_city(city_name)
      return nil unless city_name
      @geom.features.each_with_index do |val, index|
        name = val.properties['cs_name']
        return index if (city_name == name) || (city_name + ' Town' == name)
      end
      nil
    end
  end
end
