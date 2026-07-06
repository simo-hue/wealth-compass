const fs = require('fs');
const path = require('path');
const { translate } = require('bing-translate-api');

const metadataDir = path.join(__dirname, 'fastlane', 'metadata');
const sourceLocale = 'en-US';
const filesToTranslate = [
  'release_notes.txt'
];

const localeMap = {
  'ar-SA': 'ar', 'ca': 'ca', 'cs': 'cs', 'da': 'da', 'de-DE': 'de', 'el': 'el', 
  'en-AU': 'en', 'en-CA': 'en', 'en-GB': 'en', 'es-ES': 'es', 'es-MX': 'es', 
  'fi': 'fi', 'fr-CA': 'fr', 'fr-FR': 'fr', 'he': 'he', 'hi': 'hi', 'hr': 'hr', 
  'hu': 'hu', 'id': 'id', 'it': 'it', 'ja': 'ja', 'ko': 'ko', 'ms': 'ms', 
  'nl-NL': 'nl', 'no': 'no', 'pl': 'pl', 'pt-BR': 'pt', 'pt-PT': 'pt-pt', 'ro': 'ro',
  'ru': 'ru', 'sk': 'sk', 'sv': 'sv', 'th': 'th', 'tr': 'tr', 'uk': 'uk', 
  'vi': 'vi', 'zh-Hans': 'zh-Hans', 'zh-Hant': 'zh-Hant'
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

    const releaseNotesPath = path.join(targetDir, 'release_notes.txt');
    if (fs.existsSync(releaseNotesPath)) {
      const existingContent = fs.readFileSync(releaseNotesPath, 'utf8').trim();
      if (existingContent !== sourceContent['release_notes.txt']) {
        console.log(`Skipping ${locale} because it's already translated.`);
        continue;
      }
    }

    console.log(`Retrying via Bing for ${locale}...`);

    for (const file of filesToTranslate) {
      const content = sourceContent[file];
      if (!content) continue;

      try {
        const res = await translate(content, null, targetLang);
        fs.writeFileSync(path.join(targetDir, file), res.translation);
        console.log(`  - Translated ${file} to ${locale}`);
        await delay(1000); 
      } catch (error) {
        console.error(`  - Failed ${file} for ${locale}:`, error.message);
        fs.writeFileSync(path.join(targetDir, file), content);
      }
    }
  }
  console.log("Bing Retry complete!");
}
run();
