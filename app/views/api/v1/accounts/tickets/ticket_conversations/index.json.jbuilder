json.payload do
  json.array! @links do |link|
    conv = link.conversation
    json.display_id conv.display_id
    json.inbox_id conv.inbox_id
    json.inbox_name conv.inbox&.name
    json.contact_name conv.contact&.name
  end
end
