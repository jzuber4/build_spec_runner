module CodeBuildLocal

  # Module for defining objects that provide CodeBuild project sources.
  #
  # @todo Make a GitSourceProvider implmentation, for referencing
  #   CodeBuild projects by Git repo.
  #
  # See {SourceProvider::FolderSourceProvider} for the only implementation so far.

  module SourceProvider

    # A {SourceProvider} that provides the source by simply taking a file path.

    class FolderSourceProvider
      include SourceProvider

      # @!attribute [r] path
      #   @return [String] the path to the project source
      attr_accessor :path

      def initialize path
        @path = path.freeze
      end
    end
  end
end
