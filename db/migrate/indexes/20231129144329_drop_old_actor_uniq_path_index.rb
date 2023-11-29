class DropOldActorUniqPathIndex < Mongoid::Migration
  def self.up
    Actor.collection.indexes.drop_one('actor_path_unique') rescue nil
  end
end
