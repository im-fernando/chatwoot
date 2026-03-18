json.id comment.id
json.content comment.content
json.created_at comment.created_at.to_i
json.user do
  json.partial! 'api/v1/models/agent', formats: [:json], resource: comment.user
end
