# frozen_string_literal: true

require "test_helper"
require "action_text/editor/lexxy_editor"

module ActionText
  class Editor::LexxyEditorTest < ActionView::TestCase
    test "is registered with the engine" do
      assert_instance_of ActionText::Editor::LexxyEditor, RichText.editors.fetch(:lexxy)
    end

    test "#as_canonical keeps the canonical Action Text format" do
      expected = %(<p>hello, world</p><action-text-attachment sgid="123" content-type="image/png"></action-text-attachment>)
      fragment = Fragment.wrap(expected)
      editor = ActionText::Editor::LexxyEditor.new

      actual = editor.as_canonical(fragment)

      assert_kind_of Fragment, actual
      assert_dom_equal expected, actual.to_html
    end

    test "#as_editable keeps the canonical Action Text format" do
      expected = %(<p>hello, world</p><action-text-attachment sgid="123" content-type="image/png"></action-text-attachment>)
      fragment = Fragment.wrap(expected)
      editor = ActionText::Editor::LexxyEditor.new

      actual = editor.as_editable(fragment)

      assert_kind_of Fragment, actual
      assert_dom_equal expected, actual.to_html
    end

    test "#editor_name removes the Editor suffix" do
      editor = ActionText::Editor::LexxyEditor.new

      assert_equal "lexxy", editor.editor_name
    end

    test "#editor_tag returns a renderable" do
      editor = ActionText::Editor::LexxyEditor.new

      render(editor.editor_tag(name: "message[body]", value: "<p>hello</p>"))

      lexxy_editor = rendered.html.at("lexxy-editor")
      assert_equal "message[body]", lexxy_editor["name"]
      assert_equal "<p>hello</p>", lexxy_editor["value"]
      assert_equal "lexxy-content", lexxy_editor["class"]
      assert_dom "input[type=hidden]", count: 0
    end

    test "#editor_tag escapes an HTML safe :value" do
      editor = ActionText::Editor::LexxyEditor.new

      render(editor.editor_tag(value: %(<pre>&lt;lexxy-editor value="x"&gt;</pre>).html_safe))

      assert_equal %(<pre>&lt;lexxy-editor value="x"&gt;</pre>), rendered.html.at("lexxy-editor")["value"]
    end

    test "#editor_tag renders its block as children" do
      editor = ActionText::Editor::LexxyEditor.new

      render(editor.editor_tag(value: "<p>hello</p>") { tag.lexxy_prompt(trigger: "@") })

      assert_dom "lexxy-editor[value=?] > lexxy-prompt[trigger=?]", "<p>hello</p>", "@"
    end
  end
end
