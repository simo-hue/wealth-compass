const fs = require('fs');
const path = require('path');

const metadataDir = path.join(__dirname, 'fastlane', 'metadata');
const locales = fs.readdirSync(metadataDir).filter(f => fs.statSync(path.join(metadataDir, f)).isDirectory());

const supportUrl = "https://simo-hue.github.io/wealth-compass/faq"; 
const privacyUrl = "https://simo-hue.github.io/wealth-compass/privacy";
const marketingUrl = "https://simo-hue.github.io/wealth-compass/terms";

for (const locale of locales) {
  fs.writeFileSync(path.join(metadataDir, locale, 'support_url.txt'), supportUrl);
  fs.writeFileSync(path.join(metadataDir, locale, 'privacy_url.txt'), privacyUrl);
  fs.writeFileSync(path.join(metadataDir, locale, 'marketing_url.txt'), marketingUrl);
}
console.log("Applied accurate Support, Privacy, and Terms URLs to all 38 languages!");
