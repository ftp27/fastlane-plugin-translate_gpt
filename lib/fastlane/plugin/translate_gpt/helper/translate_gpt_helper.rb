require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class TranslateGptHelper
      # Read the strings file into a hash
      # @param localization_file [String] The path to the strings file
      # @return [Hash] The strings file as a hash
      def self.get_strings(localization_file)
        # Read the strings file into a hash
        strings_file = File.read(localization_file)
        strings_hash = strings_file.split(/\n/).reduce({}) do |hash, line|
          match = line.match(/^"(.+)" = "(.+)";$/)
          if match
            hash[match[1]] = match[2]
          end
          hash
        end
        return strings_hash
      end

      # Get the context associated with a localization key
      # @param localization_file [String] The path to the strings file
      # @param localization_key [String] The localization key
      # @return [String] The context associated with the localization key
      def self.get_context(localization_file, localization_key)
        # read the localization file
        content = File.read(localization_file)

        # search for the comments associated with the localization key
        regex = /\/\*\*\n\s*\* @key\s+#{localization_key}\n((\s*\*.*\n)+)\s*\*\/\n\s*"#{localization_key}"/
        match = content.match(regex)

        # return the comments, if found
        if match && match.captures.size > 0
          comments = match.captures[0].strip
          return comments.gsub(/\n\s*\*\s?/, "\n").strip
        else
          return nil
        end
      end

      # Sleep for a specified number of seconds, displaying a progress bar
      # @param seconds [Integer] The number of seconds to sleep
      def self.timeout(total)
        sleep_time = 0
        while sleep_time < total
          percent_complete = (sleep_time.to_f / total.to_f) * 100.0
          progress_bar_width = 20
          completed_width = (progress_bar_width * percent_complete / 100.0).round
          remaining_width = progress_bar_width - completed_width
          print "\rTimeout ["
          print "=" * completed_width
          print " " * remaining_width
          print "] %.2f%%" % percent_complete
          $stdout.flush
          sleep(1)
          sleep_time += 1
        end
        print "\r"
        $stdout.flush
      end
    end
  end
end
