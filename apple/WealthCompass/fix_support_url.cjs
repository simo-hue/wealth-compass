const fs = require('fs');
const path = require('path');

const metadataDir = path.join(__dirname, 'fastlane', 'metadata');
const locales = fs.readdirSync(metadataDir).filter(f => fs.statSync(path.join(metadataDir, f)).isDirectory());

const supportUrl = "https://simo-hue.github.io/wealth-compass/faq"; // Placeholder

for (const locale of locales) {
  const supportUrlPath = path.join(metadataDir, locale, 'support_url.txt');
  if (!fs.existsSync(supportUrlPath) || fs.readFileSync(supportUrlPath, 'utf8').trim() === '') {
    fs.writeFileSync(supportUrlPath, supportUrl);
  }
}
console.log("Added support_url.txt to all folders.");
