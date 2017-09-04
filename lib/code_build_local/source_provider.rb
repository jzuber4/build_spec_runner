require 'fileutils'
module CodeBuildLocal
  module SourceProvider
    class FolderSourceProvider
      include SourceProvider

      def path
        @path
      end

      def initialize path
        @path = path
      end
    end
  end
end

