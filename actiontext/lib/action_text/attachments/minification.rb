# frozen_string_literal: true

module ActionText
  module Attachments
    module Minification
      extend ActiveSupport::Concern

      class_methods do
        def fragment_by_minifying_attachments(content)
          Fragment.wrap(content).replace(Attachment::SELECTOR) do |node|
            if source_content = node["content"].presence
              value = fragment_by_minifying_attachments(source_content).to_s
              if source_content == value && node.child_nodes.empty?
                node
              else
                Okra::HTML.element_node(node.name, node.attributes.map do |attribute|
                  key, _ = attribute
                  if key == "content"
                    [key, value]
                  else
                    attribute
                  end
                end, [])
              end
            elsif node.child_nodes.empty?
              node
            else
              Okra::HTML.element_node(node.name, node.attributes, [])
            end
          end
        end
      end
    end
  end
end
