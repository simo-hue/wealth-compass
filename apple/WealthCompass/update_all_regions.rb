require 'xcodeproj'
project_path = 'WealthCompass.xcodeproj'
project = Xcodeproj::Project.open(project_path)

all_apple_regions = [
  'en', 'fr', 'de', 'it', 'ja', 'ko', 'pt-BR', 'pt-PT', 'ru', 'es', 'es-419', 
  'tr', 'ar', 'ca', 'hr', 'cs', 'da', 'nl', 'fi', 'el', 'he', 'hi', 'hu', 
  'id', 'ms', 'no', 'pl', 'ro', 'sk', 'sv', 'th', 'uk', 'vi', 'zh-Hans', 'zh-Hant', 'Base'
]

project.root_object.known_regions = (project.root_object.known_regions + all_apple_regions).uniq

project.save
puts "Added all Apple supported regions."
