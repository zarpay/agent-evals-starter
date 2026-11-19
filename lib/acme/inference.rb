# frozen_string_literal: true

module Acme
  # The one seam between Acme and a model: OpenRouter's chat completions,
  # with tools. Production and the evals both call through here, so an eval
  # measures exactly the request production sends.
  #
  # A call says what it is for. `purpose: :eval` labels it in OpenRouter's
  # app attribution, so evaluation spend is told apart from production's.
  module Inference
    URL = URI('https://openrouter.ai/api/v1/chat/completions')
    DEFAULT_MODEL = ENV.fetch('ACME_MODEL', 'anthropic/claude-haiku-5.5')

    class Error < StandardError; end

    # One tool the model asked to call.
    ToolCall = Data.define(:id, :name, :input)

    # What the model answered: its text, the tools it asked for, and the raw
    # message, which goes back into the conversation as it came.
    Response = Data.define(:text, :tool_calls, :message)

    module_function

    # @param request [Hash] { messages:, tools: } in OpenAI's chat format
    # @param model [String] an OpenRouter model id
    # @param purpose [Symbol] :production or :eval
    # @return [Response]
    def generate(request, model: DEFAULT_MODEL, purpose: :production)
      body = post(request.merge(model:), purpose:)
      message = body.dig('choices', 0, 'message') or raise Error, "no message in #{body.to_json[0, 300]}"
      Response.new(text: message['content'], tool_calls: tool_calls(message), message:)
    end

    # The request with the model's answer and each tool's result appended,
    # ready for the next turn.
    #
    # @param results [Array<Array(ToolCall, Object)>] each call with what it returned
    # @return [Hash]
    def extend_request(request, response:, results:)
      answered = results.map do |call, result|
        { role: 'tool', tool_call_id: call.id, content: result.to_json }
      end
      request.merge(messages: request[:messages] + [response.message] + answered)
    end

    def tool_calls(message)
      Array(message['tool_calls']).map do |call|
        ToolCall.new(id: call['id'], name: call.dig('function', 'name'),
                     input: JSON.parse(call.dig('function', 'arguments').presence || '{}'))
      end
    end

    def post(payload, purpose:)
      request = Net::HTTP::Post.new(URL, 'Content-Type' => 'application/json',
                                         'Authorization' => "Bearer #{ENV.fetch('OPENROUTER_API_KEY')}",
                                         'X-Title' => "Acme (#{purpose})")
      request.body = payload.to_json
      response = Net::HTTP.start(URL.host, URL.port, use_ssl: true, read_timeout: 120) { _1.request(request) }
      raise Error, "OpenRouter answered #{response.code}: #{response.body.to_s[0, 300]}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
