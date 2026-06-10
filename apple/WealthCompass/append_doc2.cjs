const fs = require('fs');

const docPath = 'DOCUMENTATION.md';
const date = new Date().toLocaleString();
const newEntry = `
- [${date}]: Internationalization (i18n) Expanded Worldwide
  - *Details*: Registered all ~40 core Apple-supported localization regions to the Xcode project and populated the \`Localizable.xcstrings\` catalog.
  - *Tech Notes*:
    - Added regions including \`fr\`, \`ja\`, \`ko\`, \`pt-BR\`, \`hi\`, \`ru\`, \`tr\`, \`nl\`, \`sv\`, \`da\`, \`fi\`, \`no\`, \`el\`, \`he\`, \`id\`, \`ms\`, \`th\`, \`vi\`, etc.
    - Updated \`Localizable.xcstrings\` with placeholder entries marked as \`needs_review\` for all new languages.
`;

if (fs.existsSync(docPath)) {
  fs.appendFileSync(docPath, newEntry, 'utf8');
} else {
  fs.writeFileSync(docPath, newEntry, 'utf8');
}
console.log("DOCUMENTATION.md updated.");
