require 'xcodeproj'
project_path = 'WealthCompass.xcodeproj'
project = Xcodeproj::Project.open(project_path)
file_path = 'Sources/Shared/Services/APIConfiguration.swift'

# Find the group
group = project.main_group.find_subpath('WealthCompass/Sources/Shared/Services', true)
if group.nil?
  puts "Group not found"
  exit 1
end

# Check if file is already in the project
file_ref = group.files.find { |f| f.path == 'APIConfiguration.swift' }
if file_ref.nil?
  file_ref = group.new_file(file_path)
  puts "Added file reference"
end

# Add to targets
['WealthCompassMac', 'WealthCompassMobile'].each do |target_name|
  target = project.targets.find { |t| t.name == target_name }
  if target
    unless target.source_build_phase.files.any? { |f| f.file_ref == file_ref }
      target.source_build_phase.add_file_reference(file_ref)
      puts "Added to target #{target_name}"
    end
  end
end

project.save
puts "Project saved"
