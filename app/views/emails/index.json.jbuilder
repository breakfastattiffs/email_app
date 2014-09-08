json.array!(@emails) do |email|
  json.extract! email, :id, :to, :subject, :body, :attachment, :status, :sending_service, :updated_at
  json.url email_url(email, format: :json)
end
