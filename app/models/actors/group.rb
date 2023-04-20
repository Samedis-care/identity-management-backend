module Actors

  class Group < Actor

    def self.global_admins
      @@global_admins ||= where(short_name: :global_admins).first_or_create(system: true, write_protected: true)
    end

  end

end
