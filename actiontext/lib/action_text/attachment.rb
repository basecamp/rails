# frozen_string_literal: true

require "active_support/core_ext/object/try"

module ActionText
  class Attachment
    include Attachments::TrixConversion, Attachments::Minification, Attachments::Caching

    mattr_accessor :tag_name, default: "action-text-attachment"

    SELECTOR = ->(node) { node.name == tag_name }
    ATTRIBUTES = %w( sgid content-type url href filename filesize width height previewable presentation caption content )

    class << self
      def fragment_by_canonicalizing_attachments(content)
        fragment_by_minifying_attachments(fragment_by_converting_trix_attachments(content))
      end

      def from_node(node, attachable = nil)
        new(node, attachable || ActionText::Attachable.from_node(node))
      end

      def from_attachables(attachables)
        Array(attachables).filter_map { |attachable| from_attachable(attachable) }
      end

      def from_attachable(attachable, attributes = {})
        if node = node_from_attributes(attachable.to_rich_text_attributes(attributes))
          new(node, attachable)
        end
      end

      def from_attributes(attributes, attachable = nil)
        if node = node_from_attributes(attributes)
          from_node(node, attachable)
        end
      end

      def data_attributes_from_node(node)
        node.attributes.reduce({}) do |attributes, (key, value)|
          if name = key[/^data-(.+)/, 1]
            attributes[name] = value
          end
          attributes
        end
      end

      private
        def node_from_attributes(attributes)
          if attributes = process_attributes(attributes).presence
            ActionText::HtmlConversion.create_element(tag_name, attributes)
          end
        end

        def process_attributes(attributes)
          process_attachment_attributes(attributes).merge(process_data_attributes(attributes))
        end

        def process_attachment_attributes(attributes)
          attributes.transform_keys { |key| key.to_s.underscore.dasherize }.slice(*ATTRIBUTES)
        end

        def process_data_attributes(attributes)
          data_attributes = attributes[:data] || {}
          data_attributes.transform_keys { |key| "data-#{key}" }
        end
    end

    attr_reader :node, :attachable

    delegate :to_param, to: :attachable
    delegate_missing_to :attachable

    def initialize(node, attachable)
      @node = node
      @attachable = attachable
    end

    def caption
      node_attributes["caption"].presence
    end

    def data_attributes
      @data_attributes ||= self.class.data_attributes_from_node(node)
    end

    def full_attributes
      node_attributes.merge(attachable_attributes).merge(sgid_attributes).merge(data: data_attributes)
    end

    def with_full_attributes
      self.class.from_attributes(full_attributes, attachable)
    end

    def to_plain_text
      if respond_to?(:attachable_plain_text_representation)
        attachable_plain_text_representation(caption)
      else
        caption.to_s
      end
    end

    def to_node
      node
    end

    def to_html
      HtmlConversion.node_to_html(node)
    end

    def to_s
      to_html
    end

    def inspect
      "#<#{self.class.name} attachable=#{attachable.inspect}>"
    end

    private
      def node_attributes
        @node_attributes ||= ATTRIBUTES.to_h { |name| [ name.underscore, node[name] ] }.compact
      end

      def attachable_attributes
        @attachable_attributes ||= (attachable.try(:to_rich_text_attributes) || {}).stringify_keys
      end

      def sgid_attributes
        @sgid_attributes ||= node_attributes.slice("sgid").presence || attachable_attributes.slice("sgid")
      end
  end
end
