require 'fastlane_core/ui/ui'
require 'loco_strings/parsers/xcstrings_file'
require 'json'
require 'openai'
# rubocop:disable all

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

      def prepare_xcstrings() 
        @xcfile = LocoStrings::XCStringsFile.new @params[:source_file]
        @output_hash = {}
        @to_translate = @xcfile.read
        
        if @params[:skip_translated] == true
          @to_translate = @to_translate.reject { |k, original| 
            !check_value_for_translate(
              @xcfile.unit(k, @params[:target_language]),
              original
            )
          }
        end 
      end

      def check_value_for_translate(string, orignal_string)
        return true unless string 
        if string.is_a? LocoStrings::LocoString
          return false if orignal_string.value.nil? || orignal_string.value.empty?
          return string.value.empty?
        elsif string.is_a? LocoStrings::LocoVariantions
          orignal_string.strings.each do |key, _|
            return true unless string.strings.has_key?(key)
            return true if string.strings[key].value.empty?
          end
        end
        return false
      end

      def prepare_strings() 
        @input_hash = get_strings(@params[:source_file])
        @output_hash = get_strings(@params[:target_file])
        @to_translate = filter_translated(@params[:skip_translated], @input_hash, @output_hash)
      end

      # Get the strings from a file
      def prepare_hashes() 
        if File.extname(@params[:source_file]) == ".xcstrings"
          prepare_xcstrings() 
        else
          prepare_strings() 
        end
      end

      # Log information about the input strings
      def log_input(bunch_size) 
        @translation_count = @to_translate.size
        number_of_strings = Colorizer::colorize("#{@translation_count}", :blue)
        UI.message "Translating #{number_of_strings} strings..."
        if bunch_size.nil? || bunch_size < 1
          estimated_string = Colorizer::colorize("#{@translation_count * @params[:request_timeout]}", :white)
          UI.message "Estimated time: #{estimated_string} seconds"
        else 
          number_of_bunches = (@translation_count / bunch_size.to_f).ceil
          estimated_string = Colorizer::colorize("#{number_of_bunches * @params[:request_timeout]}", :white)
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

      def translate_bunch_of_strings(bunch_size)
        bunch_index = 0
        number_of_bunches = (@translation_count / bunch_size.to_f).ceil
        @keys_associations = {}
        @to_translate.each_slice(bunch_size) do |bunch|
          begin 
            progress = (bunch_index / number_of_bunches.to_f * 100).round
            request_bunch(bunch, progress)
            bunch_index += 1
          rescue StandardError
            next
          end
          if bunch_index < number_of_bunches - 1 then wait end
        end
      end 

      def translate_bunch_with_tokenizer(max_tokens)
        string_index = 0 
        @keys_associations = {}
        current_bunch = {}
        @to_translate.each do |key, string|
          string_index += 1
          tmp_bunch = current_bunch.clone
          tmp_bunch[key] = string

          prompt = prepare_bunch_prompt tmp_bunch
          tokens = OpenAI.rough_token_count(prompt)
          if tokens > max_tokens
            if current_bunch.empty?
              string_index -= 1
              UI.error "Can't translate #{key}: string is too long"
              next
            end
            prompt = prepare_bunch_prompt current_bunch
            progress = (string_index / @translation_count.to_f * 100).round
            request_bunch(bunch, progress)
            current_bunch = {}
            current_bunch[key] = string
            if progress < 100 then wait end
          else 
            current_bunch = tmp_bunch
          end
        end

        if !current_bunch.empty?
          prompt = prepare_bunch_prompt current_bunch
          progress = (string_index / @translation_count.to_f * 100).round
          request_bunch(current_bunch, progress)
        end

      end 

      def request_bunch(bunch, progress) 
        UI.message "[#{progress}%] Translating #{bunch.size} strings..."
        prompt = prepare_bunch_prompt bunch
        if prompt.empty?
          UI.important "Empty prompt, skipping bunch"
          raise "Empty prompt"
        end
        max_retries = 10
        times_retried = 0

        # translate the source string to the target language
        begin
          request_bunch_translate(bunch, prompt, progress)
        rescue Net::ReadTimeout => error
          if times_retried < max_retries
            times_retried += 1
            UI.important "Failed to request translation, retry #{times_retried}/#{max_retries}"
            wait 1
            retry
          else
            UI.error "Can't translate the bunch: #{error}"
          end
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

      def prepare_bunch_prompt(strings)
        prompt = "I want you to act as a translator for a mobile application strings. " + \
            "Try to keep length of the translated text. " + \
            "You need to response with a JSON only with the translation and nothing else until I say to stop it. "
        if @params[:context] && !@params[:context].empty?
          prompt += "This app is #{@params[:context]}. "
        end
        prompt += "Translate next text from #{@params[:source_language]} to #{@params[:target_language]}:\n"

        json_hash = []
        strings.each do |key, string|
          # UI.message "Translating #{key} - #{string.value}"
          next if string.nil?

          string_hash = {}
          context = string.comment
          string_hash["context"] = context if context && !context.empty?

          key = transform_string(string.key)
          @keys_associations[key] = string.key
          string_hash["key"] = key

          if string.is_a? LocoStrings::LocoString
            next if string.value.nil? || string.value.empty?
            string_hash["string_to_translate"] = string.value
          elsif string.is_a? LocoStrings::LocoVariantions
            variants = {}
            string.strings.each do |key, variant|
              next if variant.nil? || variant.value.nil? || variant.value.empty?
              variants[key] = variant.value
            end
            string_hash["strings_to_translate"] = variants
          else 
            UI.warning "Unknown type of string: #{string.key}"
          end
          json_hash << string_hash
        end
        return '' if json_hash.empty?
        prompt += "'''\n"
        prompt += json_hash.to_json
        prompt += "\n'''"
        return prompt
      end

      def transform_string(input_string)
        uppercased_string = input_string.upcase
        escaped_string = uppercased_string.gsub(/[^0-9a-zA-Z]+/, '_')
        return escaped_string
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

      def request_bunch_translate(strings, prompt, progress)
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
        
        #key_log = Colorizer::colorize(key, :blue)
        index_log = Colorizer::colorize("[#{progress}%]", :white)
        if error
          UI.error "#{index_log} Error translating: #{error}"
        else
          target_string = response.dig("choices", 0, "message", "content")
          json_string = target_string[/\[[^\[\]]*\]/m]
          begin
            json_hash = JSON.parse(json_string)
          rescue => error
            UI.error "#{index_log} Error parsing JSON: #{error}"
            UI.error "#{index_log} JSON: \"#{json_string}\""
            return
          end
          keys_to_translate = json_hash.map { |string_hash| string_hash["key"] }
          json_hash.each do |string_hash|
            key = string_hash["key"]
            context = string_hash["context"]
            string_hash.delete("key")
            string_hash.delete("context")
            translated_string = string_hash.values.first
            return unless key && !key.empty? 
            real_key = @keys_associations[key]
            if translated_string.is_a? Hash
              strings = {}
              translated_string.each do |pl_key, value|
                UI.message "#{index_log} #{real_key}: #{pl_key} - #{value}"
                strings[pl_key] = LocoStrings::LocoString.new(pl_key, value, context)
              end
              string = LocoStrings::LocoVariantions.new(real_key, strings, context)
            elsif translated_string && !translated_string.empty?
              UI.message "#{index_log} #{real_key}: #{translated_string}"
              string = LocoStrings::LocoString.new(real_key, translated_string, context)
            end
            @output_hash[real_key] = string
            keys_to_translate.delete(key)
          end

          if keys_to_translate.length > 0
            UI.important "#{index_log} Unable to translate #{keys_to_translate.join(", ")}"
          end
        end
      end

      # Write the translated strings to the target file
      def write_output()
        number_of_strings = Colorizer::colorize("#{@output_hash.size}", :blue)  
        target_string = Colorizer::colorize(@params[:target_file], :white)
        UI.message "Writing #{number_of_strings} strings to #{target_string}..."

        if @xcfile.nil?
          file = LocoStrings.load(@params[:target_file])
          file.read
          @output_hash.each do |key, value|
            file.update(key, value.value, value.comment)
          end
          file.write
        else
          default_state = if :mark_for_review then "needs_review" else "translated" end
          @xcfile.update_file_path(@params[:target_file])
          @output_hash.each do |key, value|
            if value.is_a? LocoStrings::LocoString
              @xcfile.update(key, value.value, value.comment, default_state, @params[:target_language])
            elsif value.is_a? LocoStrings::LocoVariantions
              value.strings.each do |pl_key, variant|
                @xcfile.update_variation(key, pl_key, variant.value, variant.comment, default_state, @params[:target_language])
              end
            end
          end
          @xcfile.write
        end
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

# rubocop:enable all
