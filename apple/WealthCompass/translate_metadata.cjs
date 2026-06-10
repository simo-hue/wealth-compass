const fs = require('fs');
const path = require('path');
const { translate } = require('@vitalets/google-translate-api');

const metadataDir = path.join(__dirname, 'fastlane', 'metadata');
const sourceLocale = 'en-US';
const filesToTranslate = [
  'name.txt',
  'subtitle.txt',
  'promotional_text.txt',
  'description.txt',
  'keywords.txt',
  'release_notes.txt'
];

// Mapping from App Store Connect locales to Google Translate locales
const localeMap = {
  'ar-SA': 'ar', 'ca': 'ca', 'cs': 'cs', 'da': 'da', 'de-DE': 'de', 'el': 'el', 
  'en-AU': 'en', 'en-CA': 'en', 'en-GB': 'en', 'es-ES': 'es', 'es-MX': 'es', 
  'fi': 'fi', 'fr-CA': 'fr', 'fr-FR': 'fr', 'he': 'iw', 'hi': 'hi', 'hr': 'hr', 
  'hu': 'hu', 'id': 'id', 'it': 'it', 'ja': 'ja', 'ko': 'ko', 'ms': 'ms', 
  'nl-NL': 'nl', 'no': 'no', 'pl': 'pl', 'pt-BR': 'pt', 'pt-PT': 'pt', 'ro': 'ro',
  'ru': 'ru', 'sk': 'sk', 'sv': 'sv', 'th': 'th', 'tr': 'tr', 'uk': 'uk', 
  'vi': 'vi', 'zh-Hans': 'zh-CN', 'zh-Hant': 'zh-TW'
};

const delay = ms => new Promise(res => setTimeout(res, ms));

async function run() {
  const sourceDir = path.join(metadataDir, sourceLocale);
  
  // Read all source content
  const sourceContent = {};
  for (const file of filesToTranslate) {
    const filePath = path.join(sourceDir, file);
    if (fs.existsSync(filePath)) {
      sourceContent[file] = fs.readFileSync(filePath, 'utf8').trim();
    } else {
      sourceContent[file] = "";
    }
  }

  const locales = fs.readdirSync(metadataDir).filter(f => {
    return fs.statSync(path.join(metadataDir, f)).isDirectory() && f !== sourceLocale;
  });

  console.log(`Found ${locales.length} target locales.`);

  for (const locale of locales) {
    console.log(`Translating to ${locale}...`);
    const targetDir = path.join(metadataDir, locale);
    const targetLang = localeMap[locale];

    if (!targetLang) {
      console.log(`Skipping ${locale} - no Google Translate mapping.`);
      continue;
    }
    
    // For English variants, just copy the files verbatim
    if (targetLang === 'en') {
      for (const file of filesToTranslate) {
        if (sourceContent[file]) {
          fs.writeFileSync(path.join(targetDir, file), sourceContent[file]);
        }
      }
      continue;
    }

    for (const file of filesToTranslate) {
      const content = sourceContent[file];
      if (!content) continue;

      try {
        const { text } = await translate(content, { to: targetLang });
        fs.writeFileSync(path.join(targetDir, file), text);
        console.log(`  - Translated ${file}`);
        await delay(1500); // 1.5s delay to avoid rate limiting
      } catch (error) {
        console.error(`  - Failed ${file} for ${locale}:`, error.message);
        // Fallback to English
        fs.writeFileSync(path.join(targetDir, file), content);
      }
    }
  }
  
  console.log("Translation complete!");
}

run();
