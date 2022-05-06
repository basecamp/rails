# frozen_string_literal: true

module ActionText
  module HtmlConversion
    extend self

    def node_to_html(node)
      node.to_html
    end

    def fragment_for_html(html)
      Okra::HTML.parse_fragment(html)
    end

    def create_element(tag_name, attributes = {}, child_nodes = [])
      Okra::HTML.element_node(tag_name, attributes.map do |name, value|
        string_value = attributes[name].to_s
        string_value.empty? ? [name.to_s] : [name.to_s, string_value]
      end, child_nodes)
    end
  end
end
