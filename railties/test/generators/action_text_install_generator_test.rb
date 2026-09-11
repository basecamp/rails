# frozen_string_literal: true

require "generators/generators_test_helper"
require "generators/action_text/install/install_generator"

class ActionText::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  include GeneratorsTestHelper

  setup do
    Rails.application = Rails.application.class
    Rails.application.config.root = Pathname(destination_root)

    FileUtils.mkdir_p("#{destination_root}/app/javascript")
    FileUtils.touch("#{destination_root}/app/javascript/application.js")

    FileUtils.mkdir_p("#{destination_root}/app/assets/stylesheets")

    FileUtils.mkdir_p("#{destination_root}/config")
    FileUtils.touch("#{destination_root}/config/importmap.rb")
  end

  teardown do
     Rails.application = Rails.application.instance
   end

  test "installs JavaScript dependencies with yarn by default" do
    FileUtils.touch("#{destination_root}/package.json")

    run_generator_instance
    assert_includes @run_commands, "yarn add trix"
    assert_includes @run_commands, "yarn add @rails/actiontext"
  end

  test "installs JavaScript dependencies with yarn when yarn.lock exists" do
    FileUtils.touch("#{destination_root}/package.json")
    FileUtils.touch("#{destination_root}/yarn.lock")

    run_generator_instance
    assert_includes @run_commands, "yarn add trix"
    assert_includes @run_commands, "yarn add @rails/actiontext"
  end

  test "installs JavaScript dependencies with npm when package-lock.json exists" do
    FileUtils.touch("#{destination_root}/package.json")
    FileUtils.touch("#{destination_root}/package-lock.json")

    run_generator_instance
    assert_includes @run_commands, "npm install trix"
    assert_includes @run_commands, "npm install @rails/actiontext"
  end

  test "installs JavaScript dependencies with pnpm when pnpm-lock.yaml exists" do
    FileUtils.touch("#{destination_root}/package.json")
    FileUtils.touch("#{destination_root}/pnpm-lock.yaml")

    run_generator_instance
    assert_includes @run_commands, "pnpm add trix"
    assert_includes @run_commands, "pnpm add @rails/actiontext"
  end

  test "installs JavaScript dependencies with bun when bun.lockb exists" do
    FileUtils.touch("#{destination_root}/package.json")
    FileUtils.touch("#{destination_root}/bun.lockb")

    run_generator_instance
    assert_includes @run_commands, "bun add trix"
    assert_includes @run_commands, "bun add @rails/actiontext"
  end

  test "installs JavaScript dependencies with bun when bun.lock exists" do
    FileUtils.touch("#{destination_root}/package.json")
    FileUtils.touch("#{destination_root}/bun.lock")

    run_generator_instance
    assert_includes @run_commands, "bun add trix"
    assert_includes @run_commands, "bun add @rails/actiontext"
  end

  test "throws warning for missing entry point" do
    FileUtils.rm("#{destination_root}/app/javascript/application.js")
    output = run_generator_instance
    assert_match "You must import the @rails/actiontext JavaScript module", output
    assert_match "You must import the trix JavaScript module", output
  end

  test "imports JavaScript dependencies in application.js" do
    run_generator_instance

    assert_file "app/javascript/application.js" do |content|
      assert_match %r"^#{Regexp.escape 'import "@rails/actiontext"'}", content
      assert_match %r"^#{Regexp.escape 'import "trix"'}", content
    end
  end

  test "pins JavaScript dependencies in importmap.rb" do
    run_generator_instance

    assert_file "config/importmap.rb" do |content|
      assert_match %r|pin "@rails/actiontext"|, content
      assert_match %r|pin "trix"|, content
    end
  end

  test "creates Action Text stylesheet" do
    run_generator_instance
    assert_file "app/assets/stylesheets/actiontext.css", /^trix-editor \{/
  end

  test "creates Active Storage view partial" do
    run_generator_instance
    assert_file "app/views/active_storage/blobs/_blob.html.erb"
  end

  test "creates Action Text content view layout" do
    run_generator_instance
    assert_file "app/views/layouts/action_text/contents/_content.html.erb", <<~ERB
      <div class="trix-content">
        <%= yield -%>
      </div>
    ERB
  end

  test "creates migrations" do
    run_generator_instance
    assert_migration "db/migrate/create_active_storage_tables.active_storage.rb"
    assert_migration "db/migrate/create_action_text_tables.action_text.rb"
  end

  test "does not add a gem when installing Trix" do
    run_generator_instance ["--editor=trix"]
    assert_empty @bundle_commands
  end

  test "adds the lexxy gem when installing Lexxy" do
    run_generator_instance ["--editor=lexxy"]
    assert_includes @bundle_commands, ["add lexxy", {}, { quiet: true }]
  end

  test "does not add the lexxy gem when the Gemfile already includes it" do
    File.write("#{destination_root}/Gemfile", %(gem "lexxy"\n))

    run_generator_instance ["--editor=lexxy"]
    assert_empty @bundle_commands
  end

  test "installs Lexxy JavaScript dependencies" do
    FileUtils.touch("#{destination_root}/package.json")

    run_generator_instance ["--editor=lexxy"]
    assert_includes @run_commands, "yarn add @37signals/lexxy"
    assert_includes @run_commands, "yarn add @rails/activestorage"
    assert_not_includes @run_commands, "yarn add trix"
    assert_not_includes @run_commands, "yarn add @rails/actiontext"
  end

  test "imports Lexxy in application.js when using import maps" do
    run_generator_instance ["--editor=lexxy"]

    assert_file "app/javascript/application.js" do |content|
      assert_match %r"^#{Regexp.escape 'import "lexxy"'}$", content
      assert_no_match %r"trix|@rails/actiontext", content
    end
  end

  test "imports the Lexxy package in application.js when using a JavaScript bundler" do
    FileUtils.rm("#{destination_root}/config/importmap.rb")
    FileUtils.touch("#{destination_root}/package.json")

    run_generator_instance ["--editor=lexxy"]
    assert_file "app/javascript/application.js", %r"^#{Regexp.escape 'import "@37signals/lexxy"'}$"
  end

  test "pins Lexxy JavaScript dependencies in importmap.rb" do
    run_generator_instance ["--editor=lexxy"]

    assert_file "config/importmap.rb" do |content|
      assert_match %r|pin "lexxy", to: "lexxy.js"|, content
      assert_match %r|pin "@rails/activestorage", to: "activestorage.esm.js"|, content
      assert_no_match %r|trix|, content
    end
  end

  test "throws warning for missing entry point when installing Lexxy" do
    FileUtils.rm("#{destination_root}/app/javascript/application.js")
    output = run_generator_instance ["--editor=lexxy"]
    assert_match "You must import the lexxy JavaScript module", output
  end

  test "creates Action Text stylesheet with Lexxy styles" do
    run_generator_instance ["--editor=lexxy"]
    assert_file "app/assets/stylesheets/actiontext.css", /^@import url\("lexxy\.css"\);$/
  end

  test "creates Action Text content view layout for Lexxy" do
    run_generator_instance ["--editor=lexxy"]
    assert_file "app/views/layouts/action_text/contents/_content.html.erb", <<~ERB
      <div class="lexxy-content">
        <%= yield -%>
      </div>
    ERB
  end

  private
    def run_generator_instance(options = [])
      @run_commands = []
      @bundle_commands = []
      run_command_stub = -> (command, *) { @run_commands << command }
      bundle_command_stub = -> (command, *args) { @bundle_commands << [command, *args] }

      generator([], options).stub :run, run_command_stub do
        generator.stub :bundle_command, bundle_command_stub do
          quietly { with_database_configuration { super() } }
        end
      end
    end
end
