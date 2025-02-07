class HarmonizeActorPathSeperator < Mongoid::Migration
  # ensures every path is " / " separated (including sourrounding spaces)
  def self.up
    Actor.all.merge_rebuild_path!
  end
end
