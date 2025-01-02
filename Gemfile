source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem 'rails', '~> 8.0'

gem 'bcrypt'
gem 'bootsnap', require: false
gem 'csv'
gem 'enumerize'
gem 'ffaker'
gem 'mongoid'
gem 'mongoid-locker'
gem 'mongoid_rails_migrations'
gem 'mongoid_search'
gem 'mongoid-tree', require: 'mongoid/tree'
gem 'nokogiri'
gem 'psych', '< 4' # https://stackoverflow.com/a/71192990/9156535
gem 'snappy'
gem 'strip_attributes'

gem 'oj'

# Fastest solution for JSON:API serialization
gem 'jsonapi-serializer'

gem 'kaminari-mongoid'

# Integration rspec tests as source for describing swagger 2.0
gem 'json-schema_builder'
gem 'rspec'
gem 'rspec-rails'
gem 'rswag'

# Replacement for ActiveStorage to use S3 stored file uploads with mongodb
gem 'aws-sdk-s3', '~> 1.14'
gem 'shrine'
gem 'shrine-mongoid'

# For imageprocessing in shrine uploaders
gem 'image_processing'
gem 'ruby-vips'

# HTTP client for microservice communication
gem 'sawyer'

# user registration and login
# use fork of active_model_otp with updated dependencies
gem 'active_model_otp', git: 'https://github.com/neongrau/active_model_otp.git'
gem 'devise-doorkeeper'
gem 'doorkeeper'
gem 'doorkeeper-mongodb', '~> 5'
gem 'figaro'
gem 'omniauth', '>= 1.9.2'
gem 'omniauth-apple'
gem 'omniauth-google-oauth2'
gem 'omniauth-microsoft_graph'
gem 'omniauth-rails_csrf_protection'
gem 'recaptcha', require: 'recaptcha/rails'
gem 'tzinfo-data'

# Browser detection for account activity
gem 'browser', require: 'browser/browser'
gem 'geocoder'
gem 'maxminddb'

# monitoring
gem 'httparty'
gem 'sentry-rails'
gem 'sentry-ruby'

# excel generator
gem 'caxlsx'

gem 'rqrcode'

# HTTP server
gem 'puma'

gem 'awesome_print'

gem 'parallel'
gem 'ruby-progressbar'

group :development, :test, :live, :local_dev, :staging do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'brakeman'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'clipboard'
  gem 'colorize'
  gem 'mongo_logs_on_roids'
  gem 'prism'
  gem 'rubocop', require: false
  gem 'rubocop-factory_bot', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-rspec_rails', require: false
end

group :development do
  gem 'listen'
end

group :local_dev, :live, :dev do
  gem 'rails_semantic_logger', require: false
end

