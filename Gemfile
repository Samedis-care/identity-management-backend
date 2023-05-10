source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.2'

gem 'rails', '~> 7.0.4.3'
gem 'bcrypt', '~> 3.1.7'
gem 'bootsnap', '>= 1.1.0', require: false
gem 'ffaker'
gem 'mongoid'
# on apple m1 install manually via
# gem install snappy -- --with-cxxflags=\"-std=c++17\"
gem "snappy"
gem 'enumerize'
gem 'mongoid-tree', :require => 'mongoid/tree'
gem 'mongoid_search'
gem 'mongoid_rails_migrations'
gem 'mongoid-locker'
gem 'mongoid_includes'
gem 'nokogiri', '>= 1.13.4'
gem 'strip_attributes'
gem 'psych', '< 4' # https://stackoverflow.com/a/71192990/9156535

# Fastest solution for JSON:API serialization
gem 'oj'#, '~> 3.7.12'
gem 'jsonapi-serializer'

gem 'kaminari-mongoid'

# Integration rspec tests as source for describing swagger 2.0
gem 'rspec'
gem 'rspec-rails'
gem 'rswag'
gem 'json-schema_builder'

# Replacement for ActiveStorage to use S3 stored file uploads with mongodb
gem "aws-sdk-s3", "~> 1.14"
gem "shrine"#, "~> 2.0"
gem "shrine-mongoid"
#gem "shrine-storage-azureblob", git: 'https://github.com/TQsoft-GmbH/shrine-storage-azureblob.git'
# For imageprocessing in shrine uploaders
gem "image_processing", '>= 1.12.2'
gem 'ruby-vips'

# HTTP client for microservice communication
gem 'sawyer'

#User Registration and Login 
gem 'tzinfo-data'
gem 'figaro'
gem 'doorkeeper'
gem 'doorkeeper-mongodb', '~> 5.0'
gem 'devise-doorkeeper'
gem 'omniauth', '>= 1.9.2'
gem 'omniauth-google-oauth2'
gem 'omniauth-microsoft_graph'
gem 'omniauth-apple'
gem 'omniauth-rails_csrf_protection'
# gem 'omniauth-facebook'
# gem 'omniauth-twitter'
gem 'recaptcha', require: 'recaptcha/rails'
gem 'active_model_otp'

# Browser detection for account activity
gem "browser", require: "browser/browser"
gem "geocoder"
gem "maxminddb"

# monitoring
gem 'httparty'
gem 'sentry-ruby'
gem 'sentry-rails'

# excel generator
gem 'caxlsx', '~> 3.1.0'

gem "rqrcode", "~> 2.0"

# HTTP server
gem 'puma'

gem 'awesome_print'

gem 'parallel'
gem 'ruby-progressbar'

group :development, :test, :live, :local_dev, :staging do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'colorize'
  gem 'clipboard'
end

group :development do
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'google_drive'
end
