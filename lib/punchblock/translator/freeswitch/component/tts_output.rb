# encoding: utf-8

module Punchblock
  module Translator
    class Freeswitch
      module Component
        class TTSOutput < AbstractOutput
          private

          def do_output(engine)
            op = current_actor
            register_handler :es, :event_name => 'CHANNEL_EXECUTE_COMPLETE' do |event|
              op.send_complete_event! success_reason
            end
            voice = @component_node.voice || 'kal'
            application :speak, [engine, voice, @component_node.ssml.to_s].join('|')
          end
        end
      end
    end
  end
end
