# frozen_string_literal: true

module ActionText
  class AttachmentGallery
    include ActiveModel::Model

    class << self
      def fragment_by_canonicalizing_attachment_galleries(content)
        fragment_by_replacing_attachment_gallery_nodes(content) do |node|
          HtmlConversion.create_element(TAG_NAME, {}, node.child_nodes)
        end
      end

      def fragment_by_replacing_attachment_gallery_nodes(content, &replacer)
        Fragment.wrap(content).replace(SELECTOR, &replacer)
      end

      def from_node(node)
        new(node)
      end
    end

    attr_reader :node

    def initialize(node)
      @node = node
    end

    def attachments
      @attachments ||= node.where(&ATTACHMENT_SELECTOR).map do |node|
        ActionText::Attachment.from_node(node).with_full_attributes
      end
    end

    def size
      attachments.size
    end

    def inspect
      "#<#{self.class.name} size=#{size.inspect}>"
    end

    TAG_NAME = "div"

    SELECTOR = ->(node) { node.name == TAG_NAME && ATTACHMENTS_SELECTOR.call(node) }

    ATTACHMENT_SELECTOR = ->(node) { node.name == Attachment.tag_name && node["presentation"] == "gallery" }

    ATTACHMENTS_SELECTOR = ->(node) {
      elements, others = node.child_nodes.partition { |node| node.type == :element }
      elements.all?(&ATTACHMENT_SELECTOR) && elements.count > 1 && others.all? { |node| node.type == :whitespace }
    }

    private_constant :TAG_NAME, :ATTACHMENT_SELECTOR, :ATTACHMENTS_SELECTOR
  end
end
