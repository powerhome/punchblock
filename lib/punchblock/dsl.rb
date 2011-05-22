##
# DO NOT USE THIS API!
# This file is temporary, to help make testing Punchblock easier.
# THIS IS IMPERMANENT AND WILL DISAPPEAR
module Punchblock
  class DSL
    def initialize(transport, protocol, call, queue) # :nodoc:
      @transport, @protocol, @call, @queue = transport, protocol, call, queue
    end

    def accept # :nodoc:
      send @protocol::Message::Accept.new
    end

    def answer # :nodoc:
      send @protocol::Message::Answer.new
    end

    def hangup # :nodoc:
      send @protocol::Message::Hangup.new
    end

    def reject # :nodoc:
      send @protocol::Message::Reject.new
    end

    def redirect(dest) # :nodoc:
      send @protocol::Message::Redirect.new(dest)
    end

    def say(string, type = :text) # :nodoc:
      send @protocol::Message::Say.new type => string
      puts "Waiting on the queue..."
      response = @queue.pop
      # TODO: Error handling
    end

    def send(msg) # :nodoc:
      @transport.send @call, msg
    end
  end
end