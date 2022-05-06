# frozen_string_literal: true

module ActionText
  module PlainTextConversion
    include Okra::HTML::Constructors
    extend self

    def node_to_plain_text(node)
      format_text(node_to_plain_text_tree(node))
    end

    def node_to_plain_text_tree(node)
      node.replace do |node, index, lineage|
        name = node.name
        if name == "blockquote"
          format_quote(node)
        elsif name == "br"
          format_line_break(node)
        elsif name == "figcaption"
          format_caption(node)
        elsif name == "li"
          format_list_item(node, index, lineage)
        elsif blocklike?(node)
          format_block(node)
        elsif text?(node)
          node
        elsif !skippable?(node)
          node.child_nodes
        end
      end
    end

    private
      def format_quote(node)
        text_node("“#{format_text(node)}”\n\n")
      end

      def format_line_break(node)
        text_node("\n")
      end

      def format_caption(node)
        text_node("[#{format_text(node)}]")
      end

      def format_list_item(node, index, lineage)
        if lineage.parent_node&.name == "ol"
          child_nodes = lineage.parent_node.child_nodes
          original_node = child_nodes[index]
          siblings = child_nodes.select { |node| node.name == "li" }
          child_index = siblings.index(original_node)
          bullet = "#{child_index + 1}."
        else
          bullet = "•"
        end
        text_node("#{bullet} #{format_text(node)}\n")
      end

      def format_block(node)
        text_node("#{format_text(node)}#{BLOCK_ELEMENT_MARGINS[node.name]}")
      end

      def format_text(node)
        node.where { |node| node.type == :text }.map(&:content).join.chomp("")
      end

      BLOCK_ELEMENT_MARGINS = {
        "div" => "\n",
        "h1" => "\n\n",
        "ol" => "\n\n",
        "p" => "\n\n",
        "ul" => "\n\n",
        "tr" => "\n\n",
        "td" => "\n",
        "th" => "\n"
      }

      def blocklike?(node)
        BLOCK_ELEMENT_MARGINS.key?(node.name)
      end

      def skippable?(node)
        node.name == "script" || node.name == "style"
      end

      def text?(node)
        node.type == :text
      end
  end
end
