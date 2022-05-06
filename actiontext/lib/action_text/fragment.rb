# frozen_string_literal: true

module ActionText
  class Fragment
    class << self
      def wrap(fragment_or_html)
        case fragment_or_html
        when self
          fragment_or_html
        when Okra::HTML::Node
          new(fragment_or_html)
        else
          from_html(fragment_or_html)
        end
      end

      def from_html(html)
        new(ActionText::HtmlConversion.fragment_for_html(html.to_s.strip))
      end
    end

    attr_reader :source

    def initialize(source)
      @source = source
    end

    def find(&selector)
      source.where(&selector).first
    end

    def find_all(&selector)
      source.where(&selector).nodes
    end

    def replace(selector, mode = :deep, &replacer)
      update(source.where(&selector).replace(mode, &replacer))
    end

    def sanitize
      update(source.sanitize)
    end

    def update(node)
      node.equal?(source) ? self : Fragment.new(node)
    end

    def to_plain_text
      @plain_text ||= PlainTextConversion.node_to_plain_text(source)
    end

    def to_html
      @html ||= HtmlConversion.node_to_html(source)
    end

    def to_node
      source
    end

    def to_s
      to_html
    end
  end
end
