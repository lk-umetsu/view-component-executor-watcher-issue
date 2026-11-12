# frozen_string_literal: true

# Creates component and model files so that the autoload paths look like those
# of a mid-sized app. The files are spread over nested directories.

require "fileutils"

root = File.expand_path("..", __dir__)
components = Integer(ENV.fetch("COMPONENTS", "250"))
models = Integer(ENV.fetch("MODELS", "500"))

components_dir = File.join(root, "app/components/generated")
models_dir = File.join(root, "app/models/generated")
FileUtils.rm_rf([components_dir, models_dir])

components.times do |i|
  dir = File.join(components_dir, "group#{i / 5 % 10}", "sub#{i / 50}")
  FileUtils.mkdir_p(dir)
  namespace = "Generated::Group#{i / 5 % 10}::Sub#{i / 50}"
  File.write(File.join(dir, "item#{i}_component.rb"), "class #{namespace}::Item#{i}Component < ViewComponent::Base\nend\n")
  File.write(File.join(dir, "item#{i}_component.html.erb"), "<p>#{i}</p>\n")
end

models.times do |i|
  dir = File.join(models_dir, "group#{i / 5 % 10}", "sub#{i / 50}")
  FileUtils.mkdir_p(dir)
  File.write(File.join(dir, "item#{i}.rb"), "class Generated::Group#{i / 5 % 10}::Sub#{i / 50}::Item#{i}\nend\n")
end

puts "generated #{components} components (.rb + .html.erb) and #{models} models"
