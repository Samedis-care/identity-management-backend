require "shrine"
require "shrine/storage/file_system"
require "shrine/storage/s3"
#require "shrine/storage/azure_blob"
require 'maintenance_storage'

storage_config = {
  cache: Shrine::Storage::FileSystem.new("public", prefix: "uploads/cache")
}

case (ENV['SHRINE_STORAGE']||:aws_s3).to_sym
when :aws_s3
  storage_credentials = {
    bucket: ENV['AWS_S3_BUCKET'],
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
    endpoint: ENV['AWS_S3_ENDPOINT'],
    region: ENV['AWS_S3_REGION'],
    force_path_style: ENV['AWS_S3_FORCE_PATH_STYLE'].to_s.eql?('true')
  }.compact
  storage_config[:store] = Shrine::Storage::S3.new(**({
    public: false,
    ssl_verify_peer: !ENV['DISABLE_SSL_VERIFY'].to_s.eql?('true'),
    #upload_options: { acl: "public-read" }
    }.merge(storage_credentials).symbolize_keys))
when :azure
  storage_credentials = {
    public: false,
    scheme: 'https',
    account_name: ENV['AZURE_ACCOUNT_NAME'],
    access_key: ENV['AZURE_ACCESS_KEY'],
    container_name: ENV['AZURE_CONTAINER_NAME']
  }
  storage_config[:store] = Shrine::Storage::AzureBlob.new(**({
    public: false
  }.merge(storage_credentials).symbolize_keys))
when :local
  raise "ERROR: application.yml - FILES_DIRECTORY is not configured" unless ENV['FILES_DIRECTORY'].present?
  raise "ERROR: application.yml - The configured FILES_DIRECTORY: #{ENV['FILES_DIRECTORY']} does not exist!" unless Dir.exist?(ENV['FILES_DIRECTORY'])
  storage_config[:store] = Shrine::Storage::FileSystem.new(ENV['FILES_DIRECTORY'], prefix: ENV['FILES_PREFIX']||'api/files')
else
  raise "ERROR: application.yml - SHRINE_STORAGE config is missing or invalid"
end

# proxy storage though maintenance mode checker to enforce maintenance mode
storage_config[:store] = Shrine::Storage::MaintenanceStorage.new(storage_config[:store])

Shrine.storages = storage_config
Shrine.plugin :mongoid
Shrine.plugin :cached_attachment_data # enables retaining cached file across form redisplays
Shrine.plugin :restore_cached_data    # extracts metadata for assigned cached files
