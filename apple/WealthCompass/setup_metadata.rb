require 'fileutils'

fastlane_locales = [
  'ar-SA', 'ca', 'cs', 'da', 'de-DE', 'el', 'en-AU', 'en-CA', 'en-GB', 'en-US',
  'es-ES', 'es-MX', 'fi', 'fr-CA', 'fr-FR', 'he', 'hi', 'hr', 'hu', 'id',
  'it', 'ja', 'ko', 'ms', 'nl-NL', 'no', 'pl', 'pt-BR', 'pt-PT', 'ro',
  'ru', 'sk', 'sv', 'th', 'tr', 'uk', 'vi', 'zh-Hans', 'zh-Hant'
]

fastlane_metadata_dir = File.join(Dir.pwd, 'fastlane', 'metadata')

fastlane_locales.each do |locale|
  locale_dir = File.join(fastlane_metadata_dir, locale)
  FileUtils.mkdir_p(locale_dir)
  
  # Create empty files for metadata
  ['name.txt', 'subtitle.txt', 'description.txt', 'promotional_text.txt', 'keywords.txt', 'release_notes.txt'].each do |file_name|
    file_path = File.join(locale_dir, file_name)
    File.write(file_path, "") unless File.exist?(file_path)
  end
end

puts "Created fastlane metadata structure for #{fastlane_locales.length} locales."

# Create basic Deliverfile that ignores screenshots
deliverfile_path = File.join(Dir.pwd, 'fastlane', 'Deliverfile')
deliverfile_content = <<~DELIVERFILE
  # Deliverfile to ONLY manage metadata, completely ignoring screenshots
  
  skip_screenshots(true)
  overwrite_screenshots(false)
  submit_for_review(false)
  automatic_release(false)
DELIVERFILE

File.write(deliverfile_path, deliverfile_content)
puts "Created Deliverfile with skip_screenshots."
