json.payload do
  json.array! @comments do |comment|
    json.partial! 'api/v1/accounts/tickets/comment', formats: [:json], comment: comment
  end
end
