# frozen_string_literal: true

# Loaded only by the isolated continuation smoke in both producer and worker.
module QueueAdapterSmoke
  class Handler
    def self.call(message:, context:)
      Invocation.create!(task_id: context.fetch(:task_id), principal_id: context.fetch(:principal_id),
        idempotency_key: context.fetch(:idempotency_key))
      text = message.fetch(:parts).first.fetch(:text)
      return A2A::Rails::InputRequired.new("Which department?") if text == "begin"
      return A2A::Rails::InputRequired.new("Please provide the department ID") if text == "incomplete"

      raise "wrong execution input" unless text == "123"
      user_texts = context.fetch(:history).select { |entry| entry[:role].to_s == "user" }
        .map { |entry| entry.fetch(:parts).first.fetch(:text) }
      raise "lost conversation history" unless user_texts == %w[begin incomplete 123]
      raise "missing execution turn" if context.fetch(:execution_turn_id).nil?
      { "count" => 3, "total" => 35_000 }
    end
  end
end
