# Sublayer.configuration.ai_provider = Sublayer::Providers::OpenRouter
# Sublayer.configuration.ai_model = "openai/gpt-4-turbo-preview"

module Sublayer
  module Providers
    class OpenRouter
      def self.call(prompt:, output_adapter:)
        request_id = SecureRandom.uuid

        Sublayer.configuration.logger.log(:info, "OpenRouter API request", {
          model: Sublayer.configuration.ai_model,
          prompt: prompt,
          request_id: request_id,
        })

        before_request = Time.now

        response = HTTParty.post(
          "https://openrouter.ai/api/v1/chat/completions",
          headers: {
            "Authorization": "Bearer #{ENV.fetch('OPENROUTER_API_KEY')}",
            "HTTP-Referer": ENV.fetch('OPENROUTER_SITE_URL', 'http://localhost:3000'),
            "Content-Type": "application/json"
          },
          body: {
            model: Sublayer.configuration.ai_model,
            messages: [
              {
                "role": "user",
                "content": prompt
              }
            ],
            tool_choice: { type: "function", function: { name: output_adapter.name }},
            tools: [
              {
                type: "function",
                function: {
                  name: output_adapter.name,
                  description: output_adapter.description,
                  parameters: {
                    type: "object",
                    properties: output_adapter.format_properties
                  },
                  required: output_adapter.format_required
                }
              }
            ]
          }.to_json
        )

        after_request = Time.now
        response_time = after_request - before_request

        raise "Error generating with OpenRouter, error: #{response.body}" unless response.code == 200

        json_response = JSON.parse(response.body)

        Sublayer.configuration.logger.log(:info, "OpenRouter API response", {
          request_id: request_id,
          response_time: response_time,
          usage: {
            input_tokens: json_response.dig("usage", "prompt_tokens"),
            output_tokens: json_response.dig("usage", "completion_tokens"),
            total_tokens: json_response.dig("usage", "total_tokens")
          }
        })

        message = json_response.dig("choices", 0, "message")

        raise "No function called" unless message["tool_calls"]

        function_body = message.dig("tool_calls", 0, "function", "arguments")

        raise "Error generating with OpenRouter. Empty response. Try rewording your output adapter params to be from the perspective of the model. Full Response: #{json_response}" if function_body == "{}"
        raise "Error generating with OpenRouter. Error: Max tokens exceeded. Try breaking your problem up into smaller pieces." if json_response["choices"][0]["finish_reason"] == "length"

        results = JSON.parse(function_body)[output_adapter.name]
      end
    end
  end
end 