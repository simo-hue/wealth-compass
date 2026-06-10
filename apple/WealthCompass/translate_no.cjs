const fs = require('fs');
const path = require('path');
const { translate } = require('bing-translate-api');

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

const targetDir = path.join(metadataDir, 'no');
const targetLang = 'nb'; // Bing uses 'nb' for Norwegian
const sourceDir = path.join(metadataDir, sourceLocale);

const delay = ms => new Promise(res => setTimeout(res, ms));

async function run() {
  console.log(`Retrying via Bing for no (using nb)...`);
  for (const file of filesToTranslate) {
    const sourcePath = path.join(sourceDir, file);
    if (!fs.existsSync(sourcePath)) continue;
    const content = fs.readFileSync(sourcePath, 'utf8').trim();
    if (!content) continue;

    try {
      const res = await translate(content, null, targetLang);
      fs.writeFileSync(path.join(targetDir, file), res.translation);
      console.log(`  - Translated ${file}`);
      await delay(1000); 
    } catch (error) {
      console.error(`  - Failed ${file}:`, error.message);
    }
  }
  console.log("Fixed Norwegian!");
}
run();
