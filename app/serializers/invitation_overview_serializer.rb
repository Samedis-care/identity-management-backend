class InvitationOverviewSerializer
  include JSONAPI::Serializer

  attribute(:id) do |record|
    record.id.to_s
  end


  attributes(
    :invitable_type,
    :invitable_id,
    :app,
    :tenant_id
  )

end
