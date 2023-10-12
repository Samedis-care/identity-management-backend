# Override to define some extra indexes for performance
class Doorkeeper::AccessToken
  include Mongoid::Document

  index resource_owner_id: 1
  index created_at: 1
  index refresh_token: 1, _id: 1
  index({ revoked_at: 1 }, { expire_after_seconds: 7.days })

  def self.redo_indexes
    remove_indexes
    create_indexes
  end
end
