module Actors

  class User < Actor

    has_one :user, class_name: '::User', inverse_of: :actor, dependent: :destroy

    def self.global_admin
      where(name: :global_admin).first_or_create(
        system: true,
        write_protected: true,
        parent: Actor.user_container,
        auto: true,
        full_name: :global_admin
      )
    end

    def self.ensure_global_admin!
      # Create Admin account
      _actor_global_admin = Actors::User.global_admin
      _actor_global_admin.set(system: true)
      _user_global_admin = ::User.global_admin
      _user_global_admin.set(system: true)
      if (_user_global_admin.actor_id != _actor_global_admin.id)
        Actor.where(_id: _user_global_admin.actor_id).first.try(:delete)
        _user_global_admin.set(actor_id: _actor_global_admin.id)
        _user_global_admin.reload
      end
      _user_global_admin
    end

    # determines and (hard) deletes user actors without a user login
    def self.cleanup_orphans!
      _valid_user_actors = ::User.available.pluck(:actor_id).compact.reject &:blank?
      raise "this does not look right, please check manually" if _valid_user_actors.length < 1
      _orphans = Actors::User.where(:_id.nin => _valid_user_actors)
      _orphans.each do |_orphan|
        _orphan.mappings.delete_all
        _orphan.delete
      end
    end

  end

end
