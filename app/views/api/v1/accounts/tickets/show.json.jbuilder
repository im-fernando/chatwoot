json.payload do
  json.id @ticket.display_id
  json.internal_id @ticket.id
  json.title @ticket.title
  json.description @ticket.description
  json.status @ticket.status
  json.created_at @ticket.created_at.to_i
  json.updated_at @ticket.updated_at.to_i
  json.created_by do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: @ticket.created_by
  end
  if @ticket.assignee
    json.assignee do
      json.partial! 'api/v1/models/agent', formats: [:json], resource: @ticket.assignee
    end
  else
    json.assignee nil
  end
  json.conversations @ticket.ticket_conversations do |link|
    conv = link.conversation
    json.display_id conv.display_id
    json.inbox_id conv.inbox_id
    json.inbox_name conv.inbox&.name
    json.contact_name conv.contact&.name
  end
  json.comments @ticket.ticket_comments.chronological do |comment|
    json.partial! 'api/v1/accounts/tickets/comment', formats: [:json], comment: comment
  end
end
