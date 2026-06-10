require 'xcodeproj'

project_path = '/Users/simo/Developer/wealth-compass-1/apple/WealthCompass/WealthCompass.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'WealthCompassMac' }

# Remove all bad references anywhere
target.source_build_phase.files_references.each do |f|
  if f && f.path && f.path.include?('MacOnboardingView.swift')
    target.source_build_phase.remove_file_reference(f)
  end
end

project.main_group.recursive_children.each do |f|
  if f.class == Xcodeproj::Project::Object::PBXFileReference && f.path && f.path.include?('MacOnboardingView.swift')
    f.remove_from_project
  end
end

group = project.main_group.find_subpath(File.join('Sources', 'macOS', 'Views'), true)
file_ref = group.new_reference('Sources/macOS/Views/MacOnboardingView.swift')
file_ref.source_tree = 'SOURCE_ROOT'

target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Fixed MacOnboardingView.swift using SOURCE_ROOT in target #{target.name}"
