# frozen_string_literal: true

require "application_system_test_case"

class LexxyEditorTest < ApplicationSystemTestCase
  setup do
    @previous_editor = ActionText::RichText.editor
    ActionText::RichText.editor = ActionText::RichText.editors.fetch(:lexxy)

    visit new_message_url
    assert_selector "lexxy-editor[connected]"
  end

  teardown do
    ActionText::RichText.editor = @previous_editor
  end

  test "renders a Lexxy editor" do
    assert_selector :element, "lexxy-editor", id: "message_content", name: "message[content]"
    assert_no_selector "trix-editor"
  end

  test "filling in a rich-text area by ID" do
    fill_in_rich_textarea "message_content", with: "Hello world!"
    assert_selector :rich_text_area, "message_content", text: "Hello world!"
  end

  test "filling in a rich-text area by placeholder" do
    fill_in_rich_textarea "Your message here", with: "Hello world!"
    assert_selector :rich_text_area, "Your message here", text: "Hello world!"
  end

  test "filling in a rich-text area by aria-label" do
    fill_in_rich_textarea "Message content aria-label", with: "Hello world!"
    assert_selector :rich_text_area, "Message content aria-label", text: "Hello world!"
  end

  test "filling in a rich-text area by label" do
    assert_selector :label, "Message content label", for: "message_content"
    fill_in_rich_textarea "Message content label", with: "Hello world!"
    assert_selector :rich_text_area, "Message content label", text: "Hello world!"
  end

  test "filling in a rich-text area by name" do
    fill_in_rich_textarea "message[content]", with: "Hello world!"
    assert_selector :rich_text_area, "message[content]", text: "Hello world!"
  end

  test "filling in the only rich-text area" do
    fill_in_rich_textarea with: "Hello world!"
    assert_selector :rich_text_area, text: "Hello world!"
  end

  test "filling in a rich-text area with nil" do
    fill_in_rich_textarea "message_content", with: nil
    assert_selector :rich_text_area do |rich_text_area|
      assert_empty rich_text_area.text
    end
  end

  test "saves and edits rich text" do
    fill_in_rich_textarea "message_content", with: "<p>Hello <strong>world!</strong></p>"
    click_button "Create Message"

    assert_selector "strong", text: "world!"

    click_link "Edit"
    assert_selector "lexxy-editor[connected]"
    assert_selector :rich_text_area, "message_content", text: "Hello world!"

    fill_in_rich_textarea "message_content", with: "<p>Goodbye <em>world!</em></p>"
    click_button "Update Message"

    assert_selector "em", text: "world!"
    assert_no_text "Hello"
  end
end
