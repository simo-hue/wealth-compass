require 'xcodeproj'
project_path = 'WealthCompass.xcodeproj'
project = Xcodeproj::Project.open(project_path)

group = project.main_group.find_subpath('WealthCompass/Sources/iOS/Views', true)
file_path = 'Sources/iOS/Views/OnboardingView.swift'

file_ref = group.files.find { |f| f.path == 'OnboardingView.swift' }
if file_ref.nil?
  file_ref = group.new_file(file_path)
end

target = project.targets.find { |t| t.name == 'WealthCompassMobile' }
if target
  unless target.source_build_phase.files.any? { |f| f.file_ref == file_ref }
    target.source_build_phase.add_file_reference(file_ref)
  end
end

project.save
