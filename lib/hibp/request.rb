# frozen_string_literal: true

module Hibp
  # Hibp::Request
  #
  #   Used to make requests to the hibp API
  #
  #   @see https://haveibeenpwned.com/API/v3
  #
  class Request
    attr_reader :headers

    # @param parser [Hibp::Parser] -
    #   A tool to parse and convert data into appropriate models
    #
    # @param endpoint [String] -
    #   A specific API endpoint to call appropriate method
    #
    def initialize(endpoint:, parser: Parsers::Json.new)
      @endpoint = endpoint
      @parser = parser

      @headers = {
        'Content-Type' => 'application/json',
        'User-Agent' => "Ruby HIBP-Client #{Hibp::VERSION}"
      }
    end

    # Perform a GET request
    #
    # @param params [Hash] -
    #   Additional query params
    #
    # @param headers [Hash] -
    #   Additional HTTP headers
    #
    # @raise [Hibp::ServiceError]
    #
    def get(params: nil, headers: nil)
      response = rest_client.get(@endpoint) do |request|
        configure_request(request: request, params: params, headers: headers)
      end

      @parser ? @parser.parse_response(response) : response.body
    rescue Faraday::ResourceNotFound
      nil
    rescue StandardError => e
      handle_error(e)
    end

    private

    def rest_client
      Faraday.new do |faraday|
        faraday.headers = @headers

        faraday.response(:raise_error)
        faraday.adapter(Faraday.default_adapter)
      end
    end

    def configure_request(request: nil, params: nil, headers: nil, body: nil)
      return if request.nil?

      request.params.merge!(params) if params
      request.headers.merge!(headers) if headers
      request.body = body if body
    end

    def handle_error(error)
      error_params = parsable_error?(error) ? parse_error(error) : {}

      error_to_raise = ServiceError.new(error.message, error_params)

      raise error_to_raise
    end

    def parsable_error?(error)
      error.is_a?(Faraday::ClientError) && error.response
    end

    def parse_error(error)
      error_params = {
        status_code: error.response[:status],
        raw_body: error.response[:body]
      }

      begin
        parsed_response = Oj.load(error.response[:body], {})

        return error_params unless parsed_response

        error_params[:body] = parsed_response

        %w[title detail].each do |section|
          next if parsed_response[section].nil?

          error_params[section.to_sym] = parsed_response[section]
        end
      rescue Oj::ParseError
      end

      error_params
    end
  end
end
