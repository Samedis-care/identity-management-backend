# Load the Rails application.
require_relative 'application'

# Misc custom helpers
require "#{Rails.root}/lib/string.rb"
require "#{Rails.root}/lib/base_64_string_io.rb"

# Initialize the Rails application.
Rails.application.initialize!
