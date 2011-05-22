require 'nokogiri'

module Punchblock
  module Protocol

    ##
    # This exception may be raised if a protocol error is detected.
    class ProtocolError < StandardError; end

    module Ozone
      class Message < Nokogiri::XML::Node
        BASE_OZONE_NAMESPACE    = 'urn:xmpp:ozone'
        OZONE_VERSION           = '1'
        BASE_NAMESPACE_MESSAGES = %w[accept answer hangup reject redirect]

        # Parent object that created this object, if applicable
        attr_accessor :parent, :call_id, :cmd_id

        ##
        # Create a new Ozone Message object.
        #
        # @param [Symbol, Required] Component for this new message
        # @param [Nokogiri::XML::Document, Optional] Existing XML document to which this message should be added
        #
        # @return [Ozone::Message] New Ozone Message object
        def self.new(klass, options = {})
          # Ugly hack: we have to pass in the class name because
          # self.class returns "Class" right now
          name    = klass.to_s.downcase
          element = options.has_key?(:command) ? options.delete(:command) : name
          super(element, Nokogiri::XML::Document.new).tap do |obj|
            scope = BASE_NAMESPACE_MESSAGES.include?(name) ? nil : name
            obj.set_attribute 'xmlns', [BASE_OZONE_NAMESPACE, scope, OZONE_VERSION].compact.join(':')
            # FIXME: Do I need a handle to the parent object?
            obj.parent  = options.delete :parent
            obj.call_id = options.delete :call_id
            obj.cmd_id  = options.delete :cmd_id
          end
        end

        def self.parse(call_id, cmd_id, xml)
          # TODO: Handle more than one message at a time?
          msg = xml.first
          case msg.name
          when 'offer'
            # Collect headers into an array
            headers = msg.children.inject({}) do |headers, header|
              headers[header['name']] = header['value']
              headers
            end
            call = Punchblock::Call.new call_id, msg['to'], headers
            # TODO: Acknowledge the offer?
            return call
          when 'complete'
            return Complete.new xml, :call_id => call_id, :cmd_id => cmd_id
          when 'info'
            return Info.new xml, :call_id => call_id, :cmd_id => cmd_id
          when 'end'
            puts msg.inspect
            unless msg.first && msg.first.name == 'error'
              return End.new msg.name
            end
          end
        end

        ##
        # An Ozone accept message.  This is equivalent to a SIP "180 Trying"
        #
        # @example
        #    Accept.new.to_xml
        #
        #    returns:
        #        <accept xmlns="urn:xmpp:ozone:1"/>
        class Accept < Message
          def self.new
            super 'accept'
          end
        end

        ##
        # An Ozone answer message.  This is equivalent to a SIP "200 OK"
        #
        # @example
        #    Answer.new.to_xml
        #
        #    returns:
        #        <answer xmlns="urn:xmpp:ozone:1"/>
        class Answer < Message
          def self.new
            super 'answer'
          end
        end

        ##
        # An Ozone hangup message
        #
        # @example
        #    Hangup.new.to_xml
        #
        #    returns:
        #        <hangup xmlns="urn:xmpp:ozone:1"/>
        class Hangup < Message
          def self.new
            super 'hangup'
          end
        end

        ##
        # An Ozone reject message
        #
        # @example
        #    Reject.new.to_xml
        #
        #    returns:
        #        <reject xmlns="urn:xmpp:ozone:1"/>
        class Reject < Message
          def self.new
            super 'reject'
          end
        end

        ##
        # An Ozone redirect message
        #
        # @example
        #    Redirect.new('tel:+14045551234').to_xml
        #
        #    returns:
        #        <redirect to="tel:+14045551234" xmlns="urn:xmpp:ozone:1"/>
        class Redirect < Message
          def self.new(destination)
            super('redirect').tap do |msg|
              msg.set_attribute 'to', destination
            end
          end
        end

        class Ask < Message
          ##
          # Create an ask message
          #
          # @param [String] prompt to ask the caller
          # @param [String] choices to ask the user
          # @param [Hash] options for asking/prompting a specific call
          # @option options [Integer, Optional] :timeout to wait for user input
          # @option options [String, Optional] :recognizer to use for speech recognition
          # @option options [String, Optional] :voice to use for speech synthesis
          # @option options [String, Optional] :grammar to use for speech recognition (ie - application/grammar+voxeo or application/grammar+grxml)
          #
          # @return [Ozone::Message] a formatted Ozone ask message
          #
          # @example
          #    ask 'Please enter your postal code.',
          #        '[5 DIGITS]',
          #        :timeout => 30,
          #        :recognizer => 'es-es'
          #
          #    returns:
          #      <ask xmlns="urn:xmpp:ozone:ask:1" timeout="30" recognizer="es-es">
          #        <prompt>
          #          <speak>Please enter your postal code.</speak>
          #        </prompt>
          #        <choices content-type="application/grammar+voxeo">[5 DIGITS]</choices>
          #      </ask>
          def self.new(prompt, choices, options = {})
            super('ask').tap do |msg|
              Nokogiri::XML::Builder.with(msg) do |xml|
                xml.prompt { xml.speak prompt }
                # Default is the Voxeo Simple Grammar, unless specified
                xml.choices("content-type" => options.delete(:grammar) || 'application/grammar+voxeo') { xml.text choices }
              end
            end
          end
        end

        class Say < Message
          ##
          # Creates a say with a text for Ozone
          #
          # @param [String] text to speak back to a caller
          #
          # @return [Ozone::Message] an Ozone "say" message
          #
          # @example
          #   say 'Hello brown cow.'
          #
          #   returns:
          #     <say xmlns="urn:xmpp:ozone:say:1">
          #       <speak>Hello brown cow.</speak>
          #     </say>
          def self.new(options = {})
            super('say').tap do |msg|
              text = options.delete :text
              url  = options.delete :url
              builder = Nokogiri::XML::Builder.with msg do |xml|
                xml.speak text if text
                xml.audio("url" => url) if url
              end
            end
          end

          ##
          # Pauses a running Say
          #
          # @return [Ozone::Message::Say] an Ozone pause message for the current Say
          #
          # @example
          #    say_obj.pause.to_xml
          #
          #    returns:
          #      <pause xmlns="urn:xmpp:ozone:say:1"/>
          def pause
            Say.new :pause, :parent => self
          end

          ##
          # Create an Ozone resume message for the current Say
          #
          # @return [Ozone::Message::Say] an Ozone resume message
          #
          # @example
          #    say_obj.resume.to_xml
          #
          #    returns:
          #      <resume xmlns="urn:xmpp:ozone:say:1"/>
          def resume
            Say.new :resume, :parent => self
          end

          ##
          # Creates an Ozone stop message for the current Say
          #
          # @return [Ozone::Message] an Ozone stop message
          #
          # @example
          #    stop 'say'
          #
          #    returns:
          #      <stop xmlns="urn:xmpp:ozone:say:1"/>
          def stop
            Say.new :stop, :parent => self
          end
        end

        class Conference < Message

          ##
          # Creates an Ozone conference message
          #
          # @param [String] room id to with which to create or join the conference
          # @param [Hash] options for conferencing a specific call
          # @option options [String, Optional] :audio_url URL to play to the caller
          # @option options [String, Optional] :prompt Text to speak to the caller
          #
          # @return [Object] a Blather iq stanza object
          #
          # @example
          #    conference :id => 'Please enter your postal code.',
          #               :beep => true,
          #               :terminator => '#'
          #
          #    returns:
          #      <conference xmlns="urn:xmpp:ozone:conference:1" id="1234" beep="true" terminator="#"/>
          def self.new(room_id, options = {})
            super('conference').tap do |msg|
              prompt    = options.delete :prompt
              audio_url = options.delete :audio_url

              msg.set_attribute 'id', room_id
              msg.set_attribute 'beep', 'true' if options.delete(:beep)
              msg.set_attribute 'terminator', options.delete(:terminator) if options.has_key?(:terminator)
              Nokogiri::XML::Builder.with msg do |xml|
                xml.music {
                  xml.speak prompt if prompt
                  xml.audio(:url => audio_url) if audio_url
                } if prompt || audio_url
              end
            end
          end

          ##
          # Create an Ozone mute message for the current conference
          #
          # @return [Ozone::Message::Conference] an Ozone mute message
          #
          # @example
          #    conf_obj.mute.to_xml
          #
          #    returns:
          #      <mute xmlns="urn:xmpp:ozone:conference:1"/>
          def mute
            Conference.new :mute, :parent => self
          end

          ##
          # Create an Ozone unmute message for the current conference
          #
          # @return [Ozone::Message::Conference] an Ozone unmute message
          #
          # @example
          #    conf_obj.unmute.to_xml
          #
          #    returns:
          #      <unmute xmlns="urn:xmpp:ozone:conference:1"/>
          def unmute
            Conference.new :unmute, :parent => self
          end

          ##
          # Create an Ozone conference kick message
          #
          # @return [Ozone::Message::Conference] an Ozone conference kick message
          #
          # @example
          #    conf_obj.kick.to_xml
          #
          #    returns:
          #      <kick xmlns="urn:xmpp:ozone:conference:1"/>
          def kick
            Conference.new :kick, :parent => self
          end

        end

        class Transfer < Message
          ##
          # Creates a transfer message for Ozone
          #
          # @param [String] The destination for the call transfer (ie - tel:+14155551212 or sip:you@sip.tropo.com)
          #
          # @param [Hash] options for transferring a call
          # @option options [String, Optional] :terminator
          #
          # @return [Ozone::Message::Transfer] an Ozone "transfer" message
          #
          # @example
          #   Transfer.new('sip:myapp@mydomain.com', :terminator => '#').to_xml
          #
          #   returns:
          #     <transfer xmlns="urn:xmpp:ozone:transfer:1" to="sip:myapp@mydomain.com" terminator="#"/>
          def self.new(to, options = {})
            super('transfer').tap do |msg|
              msg.set_attribute 'to', to
              options.each do |option, value|
                msg.set_attribute option.to_s, value
              end
            end
          end
        end

        class Offer < Message
          ##
          # Creates an Offer message.
          # This message may not be sent by a client; this object is used
          # to represent an offer received from the Ozone server.
          def self.parse(xml)
            msg = self.new 'offer'
            @headers = xml.to_h
          end
        end

        class End < Message
          ##
          # Creates an End message.  This signifies the end of a call.
          # This message may not be sent by a client; this object is used
          # to represent an offer received from the Ozone server.
          def self.parse(xml)
            msg = self.new 'end'
            @headers = xml.to_h
          end
        end

        class Info < Message
          def self.parse(xml, options)
            msg = self.new 'info', options
            @headers = xml.to_h
          end
        end

        class Complete < Message
          def self.parse(xml, options)
            msg = self.new 'complete', options
            @headers = xml.to_h
          end
        end
      end
    end
  end
end