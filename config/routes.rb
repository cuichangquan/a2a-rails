# frozen_string_literal: true

A2A::Rails::Engine.routes.draw do
  get "/.well-known/agent-card.json", to: "agent_cards#show", defaults: { format: :json }
  post "/a2a", to: "requests#create"
end
