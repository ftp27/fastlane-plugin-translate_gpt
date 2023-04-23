require 'fastlane/action'
require 'openai'
require_relative '../helper/translate_gpt_helper'

module Fastlane
  module Actions
    class TranslateGptAction < Action
      def self.run(params)
        client = OpenAI::Client.new(
          access_token: params[:api_token],
          request_timeout: params[:request_timeout]
        )
        
        input_hash = Helper::TranslateGptHelper.get_strings(params[:source_file])
        output_hash = Helper::TranslateGptHelper.get_strings(params[:target_file])

        if params[:skip_translated]
          to_translate = input_hash.reject { |k, v| output_hash[k] }
        else 
          to_translate = input_hash
        end

        UI.message "Translating #{to_translate.size} strings..."

        to_translate.each_with_index do |(key, value), index|
          prompt = "Translate the following string from #{params[:source_language]} to #{params[:target_language]}: #{value}"
          context = Helper::TranslateGptHelper.get_context(params[:source_file], key)
          if context && !context.empty?
            prompt += "\n\nAdditional context:\n#{context}"
          end
          if params[:context] && !params[:context].empty?
            prompt += "\n\nCommon context:\n#{params[:context]}"
          end
          # translate the source string to the target language
          response = client.chat(
            parameters: {
              model: params[:model_name], 
              messages: [{ role: "user", content: prompt}], 
              temperature: params[:temperature],
            }
          )
          # extract the translated string from the response
          error = response.dig("error", "message")
          if error
            UI.error "Error translating #{key}: #{error}"
          else
            target_string = response.dig("choices", 0, "message", "content")
            if target_string && !target_string.empty?
              UI.message "Translating #{key} - #{value} -> #{target_string}"
              output_hash[key] = target_string
            else
              UI.warning "Unable to translate #{key} - #{value}"
            end
          end
          if index < to_translate.size - 1
            Helper::TranslateGptHelper.timeout params[:request_timeout]
          end
        end

        UI.message "Writing #{output_hash.size} strings to #{params[:target_file]}..."

        # write the output hash to the output file
        File.open(params[:target_file], "w") do |file|
          output_hash.each do |key, value|
            file.puts "\"#{key}\" = \"#{value}\";"
          end
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Translate a strings file using OpenAI's GPT API"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_token,
            env_name: "GPT_API_KEY",
            description: "API token for ChatGPT",
            sensitive: true,
            code_gen_sensitive: true,
            default_value: ""
          ),
          FastlaneCore::ConfigItem.new(
            key: :model_name,
            env_name: "GPT_MODEL_NAME",
            description: "Name of the ChatGPT model to use",
            default_value: "gpt-3.5-turbo"
          ),
          FastlaneCore::ConfigItem.new(
            key: :request_timeout,
            env_name: "GPT_REQUEST_TIMEOUT",
            description: "Timeout for the request in seconds",
            default_value: 30
          ),
          FastlaneCore::ConfigItem.new(
            key: :temperature,
            env_name: "GPT_TEMPERATURE",
            description: "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic",
            type: Float,
            optional: true,
            default_value: 0.5
          ),
          FastlaneCore::ConfigItem.new(
            key: :skip_translated,
            env_name: "GPT_SKIP_TRANSLATED",
            description: "Whether to skip strings that have already been translated",
            type: Boolean,
            optional: true,
            default_value: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :source_language,
            env_name: "GPT_SOURCE_LANGUAGE",
            description: "Source language to translate from",
            default_value: "auto"
          ),
          FastlaneCore::ConfigItem.new(
            key: :target_language,
            env_name: "GPT_TARGET_LANGUAGE",
            description: "Target language to translate to",
            default_value: "en"
          ),
          FastlaneCore::ConfigItem.new(
            key: :source_file,
            env_name: "GPT_SOURCE_FILE",
            description: "The path to the Localizable.strings file to be translated",
            verify_block: proc do |value|
              UI.user_error!("Invalid file path: #{value}") unless File.exist?(value)
              UI.user_error!("Translation file must have .strings extension") unless File.extname(value) == ".strings"
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :target_file,
            env_name: "GPT_TARGET_FILE",
            description: "Path to the translation file to update",
            verify_block: proc do |value|
              UI.user_error!("Invalid file path: #{value}") unless File.exist?(value)
              UI.user_error!("Translation file must have .strings extension") unless File.extname(value) == ".strings"
            end
          ),    
          FastlaneCore::ConfigItem.new(
            key: :context,
            env_name: "GPT_COMMON_CONTEXT",
            description: "Common context for the translation",
            optional: true,
            type: String
          )                     
        ]
      end

      def self.output
        [
          ['TRANSLATED_STRING', 'The translated string'],
          ['SOURCE_LANGUAGE', 'The source language of the string'],
          ['TARGET_LANGUAGE', 'The target language of the translation']
        ]
      end

      def self.return_value
        # This action doesn't return any specific value, so we return nil
        nil
      end      

      def self.authors
        ["ftp27"]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end      
    end
  end
end
