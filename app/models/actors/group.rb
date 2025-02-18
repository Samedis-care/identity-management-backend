module Actors

  class Group < Actor

    validate :safe_role_ids

    def safe_role_ids
      @safe_role_ids ||= begin
        return unless parent_ids.include?(tenant&.profiles_ou&.id) # only needs to check profiles (below that OU)
        return unless (role_ids - tenant.available_role_ids).any? # prevent unsafe/non organization roles

        errors.add(:base, 'This group cannot have role ids that are not included within the tenant organization')
      end
    end

    def self.global_admins
      @global_admins ||= where(short_name: :global_admins).first_or_create(system: true, write_protected: true)
    end

  end

end
