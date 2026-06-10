require 'xcodeproj'
project_path = 'WealthCompass.xcodeproj'
project = Xcodeproj::Project.open(project_path)

regions = ['en', 'it', 'de', 'es', 'zh-Hans', 'ar', 'Base']
project.root_object.known_regions = (project.root_object.known_regions + regions).uniq

project.save
puts "Known regions updated"
