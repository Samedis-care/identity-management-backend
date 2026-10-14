# Strips and downcases the domain of every EmailBlacklist entry. An entry only matches an
# address when it is stored in the form Devise normalises the address to (lowercase, no
# surrounding whitespace); entries added by hand through the admin UI as "Mailinator.COM" or
# " mailinator.com " saved fine but never blocked anything. EmailBlacklist now normalises on
# save, this repairs the existing rows. See Samedis-care/samedis-care-issues#3289
#
# Normalising can make two rows identical ("Example.com" and "example.com"). The unique index
# on domain would reject the update, so each such group is merged into one row first: the
# already-normalised row wins (else the oldest), and the merged row is active if any member was.
#
# Idempotent. Not reversible (the original casing and whitespace are not kept).
# Run once per cluster - the APAC cluster (RAILS_ENV=apac) has its own data.
class NormalizeEmailBlacklistDomains < Mongoid::Migration
  def self.up
    normalised = 0
    merged = 0

    groups = EmailBlacklist.collection.find.to_a.group_by { |doc| EmailBlacklist.normalize_domain(doc['domain']) }
    groups.each do |domain, docs|
      next if domain.blank?
      next if docs.one? && docs.first['domain'].eql?(domain)

      keeper = docs.find { |doc| doc['domain'].eql?(domain) } || docs.min_by { |doc| doc['_id'] }
      others = docs - [keeper]

      # delete first: the unique index on domain would reject the keeper's update otherwise
      EmailBlacklist.collection.delete_many('_id' => { '$in' => others.map { |doc| doc['_id'] } }) if others.any?
      changes = { 'domain' => domain }
      changes['active'] = docs.any? { |doc| doc['active'].eql?(true) } if others.any?
      EmailBlacklist.collection.update_one({ '_id' => keeper['_id'] }, { '$set' => changes })
      merged += others.size
      normalised += 1
    end

    puts "EmailBlacklist: normalised #{normalised} entries, merged away #{merged} duplicates"
  end

  def self.down
    # irreversible: the original casing/whitespace is gone, and lowercase entries are correct
  end
end
