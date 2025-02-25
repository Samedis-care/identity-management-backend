require 'digest'
require 'json'

# Adds a stable checksum method to the Hash class
class Hash
  # Generates a stable SHA256 checksum, consistent across Ruby versions
  def stable_checksum
    sorted_hash = deep_sort(self)
    json = JSON.generate(sorted_hash)
    Digest::SHA256.hexdigest(json)
  end

  private

  # Recursively sorts the hash to ensure consistent key order
  def deep_sort(object)
    case object
    when Hash
      object.keys.sort.index_with { deep_sort(object[it]) }
    when Array
      object.map { deep_sort(it) }
    else
      object
    end
  end
end
