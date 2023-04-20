class TenantGroupOverviewSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end

  attribute(:group) do |record|
    record.try(:parent).try(:short_name)
  end

  attribute(:label) do |record|
    record.short_name
  end

  attribute(:description) do |record, params|
    _role_ids = params.dig(:actor_roles, record.id.to_s) || []
    _role_ids.collect { |_id|
      params.dig(:role_descriptions, _id)
    }.join('')
  end

end
