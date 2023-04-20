namespace :auto_swagger do
  require 'rails/generators'

  desc '(Re-)create all for given API version'
  task :api, [:version] => :environment do |t, args|
    unless args[:version].present? && args[:version].to_s.start_with?('v')
      raise "NO API VERSION GIVEN! usage: rails auto_swagger:api['v3']"
    end
    _route_set = Rails.application.routes.set.reject { |r| r.name.blank? }.map do |r|
      [r.name, r.defaults]
    end.to_h.with_indifferent_access.reject do |r, defaults|
      defaults.fetch(:noswagger, false)
    end

    _routes_plural = _route_set.select do |route_name, route_info|
      (route_info[:controller].start_with? "api/#{args[:version]}" rescue false) &&
        (route_name.pluralize.eql?(route_name) || route_name.ends_with?('_index'))
    end.keys.sort

    _routes_singular = _route_set.select do |route_name, route_info|
      (route_info[:controller].start_with? "api/#{args[:version]}" rescue false) &&
        (route_name.singularize.eql? route_name)
    end.keys.sort.reject do |route|
      puts "#{route.pluralize} OR #{route}_index"
      _routes_plural.include?(route.pluralize) || _routes_plural.include?("#{route}_index")
    end

    _routes = (_routes_plural + _routes_singular).sort.uniq

    if _routes.empty?
      puts "=" * 80
      puts "Could not find any routes for `api/#{args[:version]}`".red
      puts "=" * 80
    end
    _routes.each do |route|
      begin
        puts "Processing Route: " + (_routes_plural.include?(route) ? "plural" : "singular") + " #{route}"
        Rails::Generators.invoke("auto_swagger_spec", [route, "-f"])
      rescue => e
        puts "=" * 80
        puts " There was an error trying to auto_swagger the route:\n #{route.white}".red
        puts "-" * 80
        puts " Please check:\n #{(_route_set.dig(route, :controller)+'_controller.rb').white}".red
        puts "=" * 80
        raise e
      end
    end

    puts "=" * 80
    puts " Finished creating/updating: #{"#{_routes.length} specs".white} for `api/#{args[:version]}`".green
    puts "=" * 80

  end

end
