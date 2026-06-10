const fs = require('fs');
const path = require('path');
const metadataDir = path.join(__dirname, 'fastlane', 'metadata');
const locales = fs.readdirSync(metadataDir).filter(f => fs.statSync(path.join(metadataDir, f)).isDirectory() && f !== 'en-US');

const missing = [];
for (const locale of locales) {
  const namePath = path.join(metadataDir, locale, 'name.txt');
  if (fs.existsSync(namePath)) {
    const content = fs.readFileSync(namePath, 'utf8').trim();
    if (content === 'Wealth Compass Tracker') {
      missing.push(locale);
    }
  }
}
console.log(missing.join(','));
