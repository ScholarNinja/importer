require 'json'
require 'rest_client'

class Cayley
  API_PATH = '/api/v1/'

  def initialize(host = nil, port = nil)
    @host = host || 'localhost'
    @port = port || 64210
    @path = "http://#{@host}:#{@port}#{API_PATH}"

  end

  def write(triples)
    body = triples.map do |triple|
      puts "Writing: #{triple[0]} -> #{triple[1]} -> #{triple[2]}"
      {
        subject: triple[0],
        predicate: triple[1],
        object: triple[2]
      }
    end.to_json

    RestClient.post @path + 'write', body, content_type: :json
  end
end
