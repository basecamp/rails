# frozen_string_literal: true

# :markup: markdown

require "pathname"
require "rails/generators/bundle_helper"
require "rails/generators/js_package_manager"

module ActionText
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include Rails::Generators::BundleHelper
      include Rails::Generators::JsPackageManager

      EDITORS = %w[ lexxy trix ].freeze
      LOAD_DEFAULTS = /^\s*config\.load_defaults.*\n/
      EDITOR_ASSIGNMENT = /^[ \t]*config\.action_text\.editor[ \t]*=[ \t]*:\w+[ \t]*\n/
      EDITOR_SETTING = /^[^#\n]*config\.action_text\.editor\s*=/

      source_root File.expand_path("templates", __dir__)

      class_option :editor, type: :string, enum: EDITORS,
        desc: "The rich text editor to install. Defaults to config.action_text.editor"

      def check_editor
        unless EDITORS.include?(editor)
          raise Rails::Generators::Error, "Can't install the #{editor.inspect} editor named by config.action_text.editor. " \
            "Pass --editor=lexxy or --editor=trix, or install that editor yourself."
        end
      end

      def configure_editor
        return unless options[:editor] && options[:editor] != configured_editor

        editor_setting = "config.action_text.editor = :#{editor}\n"
        application_path = File.join(destination_root, "config/application.rb")

        # Replace plain assignments with one after config.load_defaults, which would
        # otherwise replace an assignment that comes before it.
        gsub_file application_path, EDITOR_ASSIGNMENT, "" if File.read(application_path).match?(EDITOR_ASSIGNMENT)

        if File.read(application_path).match?(LOAD_DEFAULTS)
          inject_into_file application_path, optimize_indentation(editor_setting, 4), after: LOAD_DEFAULTS
        else
          environment editor_setting
        end

        conflicting_editor_settings.each do |path|
          say "#{path} sets config.action_text.editor to something other than :#{editor}, which can take precedence. Update it to :#{editor}.", :yellow
        end
      end

      def add_editor_gem
        if trix? && !gemfile_includes?("action_text-trix")
          bundle_command("add action_text-trix", {}, quiet: true)
        end
      end

      def install_javascript_dependencies
        return unless using_js_runtime?

        say "Installing JavaScript dependencies", :green
        javascript_packages.each do |package|
          run package_add_command(package)
        end
      end

      def append_javascript_dependencies
        destination = Pathname(destination_root)

        if (application_javascript_path = destination.join("app/javascript/application.js")).exist?
          javascript_modules.each do |javascript_module|
            insert_into_file application_javascript_path.to_s, %(\nimport "#{javascript_module}"\n)
          end
        else
          javascript_modules.each do |javascript_module|
            say <<~INSTRUCTIONS, :green
              You must import the #{javascript_module} JavaScript module in your application entrypoint.
            INSTRUCTIONS
          end
        end

        if (importmap_path = destination.join("config/importmap.rb")).exist?
          importmap_pins.each do |pin|
            append_to_file importmap_path.to_s, "#{pin}\n"
          end
        end
      end

      def create_actiontext_files
        template "#{editor}/actiontext.css", "app/assets/stylesheets/actiontext.css"

        gem_root = "#{__dir__}/../../../.."

        copy_file "#{gem_root}/app/views/active_storage/blobs/_blob.html.erb",
          "app/views/active_storage/blobs/_blob.html.erb"

        template "layouts/action_text/contents/_content.html.erb",
          "app/views/layouts/action_text/contents/_content.html.erb"
      end

      def create_migrations
        rails_command "railties:install:migrations FROM=active_storage,action_text", inline: true
      end

      hook_for :test_framework

      private
        def editor
          @editor ||= options[:editor] || configured_editor
        end

        def configured_editor
          if Rails.application.config.respond_to?(:action_text)
            Rails.application.config.action_text.editor.to_s
          else
            "trix"
          end
        end

        def conflicting_editor_settings
          paths = [ File.join(destination_root, "config/application.rb") ] +
            Dir[File.join(destination_root, "config/{initializers/**,environments}/*.rb")].sort

          paths.filter_map do |path|
            conflicting = File.read(path).each_line.any? do |line|
              line.match?(EDITOR_SETTING) && !line.match?(/config\.action_text\.editor\s*=\s*:#{editor}\b/)
            end

            Pathname(path).relative_path_from(destination_root).to_s if conflicting
          end
        end

        def lexxy?
          editor == "lexxy"
        end

        def trix?
          editor == "trix"
        end

        def gemfile_includes?(gem_name)
          gemfile = Pathname(destination_root).join("Gemfile")
          gemfile.exist? && gemfile.read.match?(/^\s*gem ["']#{gem_name}["']/)
        end

        def javascript_packages
          lexxy? ? %w[ @37signals/lexxy @rails/activestorage ] : %w[ trix @rails/actiontext ]
        end

        def javascript_modules
          if !lexxy?
            %w[ trix @rails/actiontext ]
          elsif importmap?
            %w[ lexxy ]
          else
            %w[ @37signals/lexxy ]
          end
        end

        def importmap_pins
          if lexxy?
            [ %(pin "lexxy", to: "lexxy.js"), %(pin "@rails/activestorage", to: "activestorage.esm.js") ]
          else
            [ %(pin "trix"), %(pin "@rails/actiontext", to: "actiontext.esm.js") ]
          end
        end

        def importmap?
          Pathname(destination_root).join("config/importmap.rb").exist?
        end
    end
  end
end
