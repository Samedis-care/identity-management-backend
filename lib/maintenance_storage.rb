require 'maintenance_mode'

class Shrine
  module Storage
    class MaintenanceStorage
      attr_accessor :chain_provider

      def initialize(chain_provider)
        self.chain_provider = chain_provider
        # check if optional methods are implemented and remove implementation if not
        undef presign unless self.chain_provider.respond_to? :presign
        undef delete_prefixed unless self.chain_provider.respond_to? :delete_prefixed
        undef clear! unless self.chain_provider.respond_to? :clear!
        undef update unless self.chain_provider.respond_to? :update
      end

      # fyi: `...` means all arguments
      def upload(*args, **kwargs)
        MaintenanceMode.current.raise_error :write
        chain_provider.upload(*args, **kwargs)
      end

      def open(...)
        MaintenanceMode.current.raise_error :read
        chain_provider.open(...)
      end

      def url(*args, **kwargs)
        MaintenanceMode.current.raise_error :read
        chain_provider.url(*args, **kwargs)
      end

      def exists?(...)
        MaintenanceMode.current.raise_error :read
        chain_provider.exists?(...)
      end

      def delete(*args, **kwargs)
        MaintenanceMode.current.raise_error :write
        chain_provider.delete *args, **kwargs
      end

      def presign(...)
        MaintenanceMode.current.raise_error :write
        chain_provider.presign(...)
      end

      def delete_prefixed(...)
        MaintenanceMode.current.raise_error :write
        chain_provider.delete_prefixed(...)
      end

      def clear!(...)
        MaintenanceMode.current.raise_error :write
        chain_provider.clear!(...)
      end

      def update(...)
        MaintenanceMode.current.raise_error :write
        chain_provider.update(...)
      end
    end
  end
end