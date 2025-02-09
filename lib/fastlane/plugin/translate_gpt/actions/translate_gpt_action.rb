require 'fastlane/action'
require_relative '../helper/translate_gpt_helper'
require 'loco_strings'

module Fastlane
  module Actions
    class TranslateGptAction < Action
      def self.run(params)
        helper = Helper::TranslateGptHelper.new(params)
        helper.prepare_hashes
        bunch_size = params[:bunch_size]
        max_input_tokens = params[:max_input_tokens]
        helper.log_input(bunch_size)
        if !max_input_tokens.nil? && max_input_tokens > 0
          helper.translate_bunch_with_tokenizer(max_input_tokens)
        elsif bunch_size.nil? || bunch_size < 1
          helper.translate_strings
        else
          helper.translate_bunch_of_strings(bunch_size)
        end
        helper.write_output
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
            env_name: 'GPT_API_KEY',
            description: 'API token for ChatGPT',
            sensitive: true,
            code_gen_sensitive: true,
            default_value: ''
          ),
          FastlaneCore::ConfigItem.new(
            key: :model_name,
            env_name: 'GPT_MODEL_NAME',
            description: 'Name of the ChatGPT model to use',
            default_value: 'gpt-3.5-turbo'
          ),
          FastlaneCore::ConfigItem.new(
            key: :request_timeout,
            env_name: 'GPT_REQUEST_TIMEOUT',
            description: 'Timeout for the request in seconds',
            type: Integer,
            default_value: 30
          ),
          FastlaneCore::ConfigItem.new(
            key: :temperature,
            env_name: 'GPT_TEMPERATURE',
            description: 'What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic',
            type: Float,
            optional: true,
            default_value: 0.5
          ),
          FastlaneCore::ConfigItem.new(
            key: :skip_translated,
            env_name: 'GPT_SKIP_TRANSLATED',
            description: 'Whether to skip strings that have already been translated',
            type: Boolean,
            optional: true,
            default_value: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :source_language,
            env_name: 'GPT_SOURCE_LANGUAGE',
            description: 'Source language to translate from',
            default_value: 'auto'
          ),
          FastlaneCore::ConfigItem.new(
            key: :target_language,
            env_name: 'GPT_TARGET_LANGUAGE',
            description: 'Target language to translate to',
            default_value: 'en'
          ),
          FastlaneCore::ConfigItem.new(
            key: :source_file,
            env_name: 'GPT_SOURCE_FILE',
            description: 'The path to the Localizable.strings file to be translated',
            verify_block: proc do |value|
              UI.user_error!("Invalid file path: #{value}") unless File.exist?(value)
              extension = File.extname(value)
              available_extensions = ['.strings', '.xcstrings']
              unless available_extensions.include? extension
                UI.user_error!("Translation file must have any of these extensions: #{available_extensions}")
              end
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :target_file,
            env_name: 'GPT_TARGET_FILE',
            description: 'Path to the translation file to update',
            verify_block: proc do |value|
              UI.user_error!("Invalid file path: #{value}") unless File.exist?(value)
              extension = File.extname(value)
              available_extensions = ['.strings', '.xcstrings']
              unless available_extensions.include? extension
                UI.user_error!("Translation file must have any of these extensions: #{available_extensions}")
              end
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :context,
            env_name: 'GPT_COMMON_CONTEXT',
            description: 'Common context for the translation',
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :bunch_size,
            env_name: 'GPT_BUNCH_SIZE',
            description: 'Number of strings to translate in a single request',
            optional: true,
            type: Integer
          ),
          FastlaneCore::ConfigItem.new(
            key: :max_input_tokens,
            env_name: 'GPT_MAX_INPUT_TOKENS',
            description: 'Maximum number of tokens in the input request',
            type: Integer,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :mark_for_review,
            env_name: 'GPT_MARK_FOR_REVIEW',
            description: 'If string has been translated by GPT, mark it for review',
            type: Boolean,
            optional: true,
            default_value: false
          ),
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
        ['ftp27']
      end

      def self.is_supported?(platform)
        %i[ios mac].include?(platform)
      end
    end
  end
end
