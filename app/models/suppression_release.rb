# Remembers when SuppressionList.release_bounced last took an address off the SES suppression
# list, so one address is released at most once per COOLDOWN. Without it, an invite to a
# mistyped address would be released and bounce again on every single invite.
# One tiny document per released address, the email is the _id.
class SuppressionRelease
  include Mongoid::Document

  store_in collection: 'suppression_releases'

  field :_id, type: String, overwrite: true
  field :released_at, type: Time

  COOLDOWN = 1.day

  # Atomically takes the release slot for this address. True for exactly one caller per
  # COOLDOWN, even with concurrent requests (the _id is unique, the update is conditional).
  def self.claim(email, now: Time.now.utc)
    expired = collection.update_one(
      { _id: email, released_at: { '$lt' => now - COOLDOWN } },
      { '$set' => { released_at: now } }
    )
    return true if expired.modified_count == 1

    collection.insert_one(_id: email, released_at: now)
    true
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000 # duplicate key: released within the cooldown

    false
  end

  # gives the slot back, used when the release itself failed
  def self.unclaim(email)
    collection.delete_one(_id: email)
  end
end
