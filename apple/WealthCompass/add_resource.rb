require 'xcodeproj'
project_path = 'WealthCompass.xcodeproj'
project = Xcodeproj::Project.open(project_path)
file_path = 'Sources/Shared/Resources/Localizable.xcstrings'

# Find or create the group
group = project.main_group.find_subpath('WealthCompass/Sources/Shared/Resources', true)
if group.nil?
  puts "Group not found"
  exit 1
end

# Check if file is already in the project
file_ref = group.files.find { |f| f.path == 'Localizable.xcstrings' }
if file_ref.nil?
  file_ref = group.new_file(file_path)
  puts "Added file reference"
end

# Add to targets (resources phase)
['WealthCompassMac', 'WealthCompassMobile'].each do |target_name|
  target = project.targets.find { |t| t.name == target_name }
  if target
    unless target.resources_build_phase.files.any? { |f| f.file_ref == file_ref }
      target.resources_build_phase.add_file_reference(file_ref, true)
      puts "Added to target #{target_name} resources"
    end
  end
end

project.save
puts "Project saved"
