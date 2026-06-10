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
  const sourceContent = {};
  for (const file of filesToTranslate) {
    const filePath = path.join(sourceDir, file);
    if (fs.existsSync(filePath)) {
      sourceContent[file] = fs.readFileSync(filePath, 'utf8').trim();
    } else {
      sourceContent[file] = "";
    }
  }

  const locales = fs.readdirSync(metadataDir).filter(f => fs.statSync(path.join(metadataDir, f)).isDirectory() && f !== sourceLocale);

  for (const locale of locales) {
    const targetDir = path.join(metadataDir, locale);
    const targetLang = localeMap[locale];

    if (!targetLang || targetLang === 'en') continue;

    // Check if name.txt matches English to determine if this folder failed
    const namePath = path.join(targetDir, 'name.txt');
    if (fs.existsSync(namePath)) {
      const nameContent = fs.readFileSync(namePath, 'utf8').trim();
      if (nameContent !== sourceContent['name.txt']) {
        // Already translated successfully
        continue;
      }
    }

    console.log(`Retrying translation for ${locale}...`);

    for (const file of filesToTranslate) {
      const content = sourceContent[file];
      if (!content) continue;

      try {
        const { text } = await translate(content, { to: targetLang });
        fs.writeFileSync(path.join(targetDir, file), text);
        console.log(`  - Translated ${file}`);
        await delay(4000); // 4-second delay to avoid rate limiting
      } catch (error) {
        console.error(`  - Failed ${file} for ${locale}:`, error.message);
        fs.writeFileSync(path.join(targetDir, file), content);
      }
    }
  }
  console.log("Retry complete!");
}
run();
