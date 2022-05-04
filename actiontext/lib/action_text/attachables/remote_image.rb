# frozen_string_literal: true

module ActionText
  module Attachables
    class RemoteImage
      extend ActiveModel::Naming

      class << self
        def from_node(node)
          if node["url"] && content_type_is_image?(node["content-type"])
            new(**attributes_from_node(node))
          end
        end

        private
          def content_type_is_image?(content_type)
            content_type.to_s.match?(/^image(\/.+|$)/)
          end

          def attributes_from_node(node)
            { url: node["url"],
              content_type: node["content-type"],
              width: node["width"],
              height: node["height"],
              data: Attachment.data_attributes_from_node(node) }
          end
      end

      attr_reader :url, :content_type, :width, :height, :data

      def initialize(url:, content_type:, width:, height:, data: {})
        @url = url
        @content_type = content_type
        @width = width
        @height = height
        @data = data.stringify_keys.freeze
      end

      def attachable_plain_text_representation(caption)
        "[#{caption || "Image"}]"
      end

      def to_partial_path
        "action_text/attachables/remote_image"
      end
    end
  end
end
