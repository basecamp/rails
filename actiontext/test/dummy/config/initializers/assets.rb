# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Serve Lexxy's JavaScript without loading its engine, which would replace the
# Trix editor this application uses by default.
Rails.application.config.assets.paths << Pathname(Gem.loaded_specs.fetch("lexxy").full_gem_path).join("app/assets/javascript")

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w( admin.js admin.css )
