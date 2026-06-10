require 'xcodeproj'

project_path = '/Users/simo/Developer/wealth-compass-1/apple/WealthCompass/WealthCompass.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'WealthCompassMac' }
group = project.main_group.find_subpath(File.join('Sources', 'macOS', 'Views'), true)
file_ref = group.new_reference('MacOnboardingView.swift')

if !target.source_build_phase.files_references.include?(file_ref)
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added MacOnboardingView.swift to target #{target.name}"
else
  puts "MacOnboardingView.swift is already in target #{target.name}"
end

project.save
