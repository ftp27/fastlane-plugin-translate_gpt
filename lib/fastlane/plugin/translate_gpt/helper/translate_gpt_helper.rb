require 'fastlane_core/ui/ui'
require 'loco_strings'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class TranslateGptHelper
      def initialize(params)
        @params = params
        @client = OpenAI::Client.new(
          access_token: params[:api_token],
          request_timeout: params[:request_timeout]
        )
        @timeout = params[:request_timeout]
      end

      # Get the strings from a file
      def prepare_hashes() 
        @input_hash = get_strings(@params[:source_file])
        @output_hash = get_strings(@params[:target_file])
        @to_translate = filter_translated(@params[:skip_translated], @input_hash, @output_hash)
      end

      # Log information about the input strings
      def log_input() 
        @translation_count = @to_translate.size
        number_of_strings = Colorizer::colorize("#{@translation_count}", :blue)
        UI.message "Translating #{number_of_strings} strings..."
        if @translation_count > 0 
          estimated_string = Colorizer::colorize("#{@translation_count * @params[:request_timeout]}", :white)
          UI.message "Estimated time: #{estimated_string} seconds"
        end
      end

      # Cycle through the input strings and translate them
      def translate_strings()
        @to_translate.each_with_index do |(key, string), index|
          prompt = prepare_prompt string

          max_retries = 10
          times_retried = 0

          # translate the source string to the target language
          begin
            request_translate(key, string, prompt, index)
          rescue Net::ReadTimeout => error
            if times_retried < max_retries
              times_retried += 1
              UI.important "Failed to request translation, retry #{times_retried}/#{max_retries}"
              wait 1
              retry
            else
              UI.error "Can't translate #{key}: #{error}"
            end
          end
          if index < @translation_count - 1 then wait end
        end
      end

      # Prepare the prompt for the GPT API
      def prepare_prompt(string) 
        prompt = "I want you to act as a translator for a mobile application strings. " + \
            "Try to keep length of the translated text. " + \
            "You need to answer only with the translation and nothing else until I say to stop it.  No commentaries." 
        if @params[:context] && !@params[:context].empty?
          prompt += "This app is #{@params[:context]}. "
        end 
        context = string.comment
        if context && !context.empty?
          prompt += "Additional context is #{context}. "
        end
        prompt += "Translate next text from #{@params[:source_language]} to #{@params[:target_language]}:\n" +
          "#{string.value}"
        return prompt
      end

      # Request a translation from the GPT API
      def request_translate(key, string, prompt, index)
        response = @client.chat(
          parameters: {
            model: @params[:model_name], 
            messages: [
              { role: "user", content: prompt }
            ], 
            temperature: @params[:temperature],
          }
        )
        # extract the translated string from the response
        error = response.dig("error", "message")
        key_log = Colorizer::colorize(key, :blue)
        index_log = Colorizer::colorize("[#{index + 1}/#{@translation_count}]", :white)
        if error
          UI.error "#{index_log} Error translating #{key_log}: #{error}"
        else
          target_string = response.dig("choices", 0, "message", "content")
          if target_string && !target_string.empty?
            UI.message "#{index_log} Translating #{key_log} - #{string.value} -> #{target_string}"
            string.value = target_string
            @output_hash[key] = string
          else
            UI.important "#{index_log} Unable to translate #{key_log} - #{string.value}"
          end
        end
      end

      # Write the translated strings to the target file
      def write_output()
        number_of_strings = Colorizer::colorize("#{@output_hash.size}", :blue)  
        target_string = Colorizer::colorize(@params[:target_file], :white)
        UI.message "Writing #{number_of_strings} strings to #{target_string}..."

        file = LocoStrings.load(@params[:target_file])
        file.read
        @output_hash.each do |key, value|
          file.update(key, value.value, value.comment)
        end
        file.write
      end

      # Read the strings file into a hash
      # @param localization_file [String] The path to the strings file
      # @return [Hash] The strings file as a hash
      def get_strings(localization_file)
        file = LocoStrings.load(localization_file)
        return file.read
      end

      # Get the context associated with a localization key
      # @param localization_file [String] The path to the strings file
      # @param localization_key [String] The localization key
      # @return [String] The context associated with the localization key
      def get_context(localization_file, localization_key)
        file = LocoStrings.load(localization_file)
        string = file.read[localization_key]
        return string.comment
      end

      def filter_translated(need_to_skip, base, target) 
        if need_to_skip
          return base.reject { |k, v| target[k] }
        else 
          return base
        end
      end

      # Sleep for a specified number of seconds, displaying a progress bar
      # @param seconds [Integer] The number of seconds to sleep
      def wait(seconds = @timeout)
        sleep_time = 0
        while sleep_time < seconds
          percent_complete = (sleep_time.to_f / seconds.to_f) * 100.0
          progress_bar_width = 20
          completed_width = (progress_bar_width * percent_complete / 100.0).round
          remaining_width = progress_bar_width - completed_width
          print "\rTimeout [" 
          print Colorizer::code(:green)
          print "=" * completed_width
          print " " * remaining_width
          print Colorizer::code(:reset)
          print "]"
          print " %.2f%%" % percent_complete
          $stdout.flush
          sleep(1)
          sleep_time += 1
        end
        print "\r"
        $stdout.flush
      end
    end

    # Helper class for bash colors
    class Colorizer
      COLORS = {
        black:   30,
        red:     31,
        green:   32,
        yellow:  33,
        blue:    34,
        magenta: 35,
        cyan:    36,
        white:   37,
        reset:   0,
      }
    
      def self.colorize(text, color)
        color_code = COLORS[color.to_sym]
        "\e[#{color_code}m#{text}\e[0m"
      end
      def self.code(color)
        "\e[#{COLORS[color.to_sym]}m"
      end
    end
  end
end
