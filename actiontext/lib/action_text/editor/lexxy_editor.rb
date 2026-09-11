# frozen_string_literal: true

module ActionText
  class Editor::LexxyEditor < Editor # :nodoc:
    def editor_tag(...)
      Tag.new(editor_name, ...)
    end
  end

  class Editor::LexxyEditor::Tag < Editor::Tag # :nodoc:
    def render_in(view_context, ...)
      # Lexxy reads its content from the value attribute, which must be escaped
      # even when the content is marked as HTML safe.
      options[:value] = options[:value].to_str if options[:value].respond_to?(:to_str)

      super
    end
  end
end
