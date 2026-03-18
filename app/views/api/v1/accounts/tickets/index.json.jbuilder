json.meta do
  json.count @tickets_count
  json.current_page @tickets.current_page
end

json.payload do
  json.array! @tickets do |ticket|
    json.id ticket.display_id
    json.internal_id ticket.id
    json.title ticket.title
    json.description ticket.description
    json.status ticket.status
    json.created_at ticket.created_at.to_i
    json.updated_at ticket.updated_at.to_i
    json.created_by do
      json.partial! 'api/v1/models/agent', formats: [:json], resource: ticket.created_by
    end
    if ticket.assignee
      json.assignee do
        json.partial! 'api/v1/models/agent', formats: [:json], resource: ticket.assignee
      end
    else
      json.assignee nil
    end
  end
end
