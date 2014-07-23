require 'json'
require 'rest_client'

class Cayley
  API_PATH = '/api/v1/'

  def initialize(host = nil, port = nil)
    @host = host || 'localhost'
    @port = port || 64210
    @path = "http://#{@host}:#{@port}#{API_PATH}"
  end

  def write(subject, predicate, object)
    body = [{
      subject: subject,
      predicate: predicate,
      object: object,
    }].to_json
    puts "Writing: #{subject} -> #{predicate} -> #{object}"
    RestClient.post @path + 'write', body, content_type: :json
  end
end
