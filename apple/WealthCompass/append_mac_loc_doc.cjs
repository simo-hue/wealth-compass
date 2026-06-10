const fs = require('fs');
const docPath = 'DOCUMENTATION.md';
const date = new Date().toLocaleString();
const newEntry = `
- [${date}]: macOS Localization String Extraction (Multi-Agent)
  - *Details*: Spawned 12 autonomous sub-agents to concurrently audit all Swift files in the macOS app implementation (\`Sources/macOS/\`). The agents identified and extracted over 120 unmapped hardcoded strings, while ensuring they are wrapped in \`String(localized:)\` where needed.
  - *Tech Notes*:
    - All extracted strings were aggregated and added to \`Sources/Shared/Resources/Localizable.xcstrings\`.
    - Executed \`update_catalog_all.cjs\` to ensure the newly added strings received the \`needs_review\` state across all 40 supported Apple language regions.
`;

fs.appendFileSync(docPath, newEntry, 'utf8');
console.log("DOCUMENTATION.md updated.");
