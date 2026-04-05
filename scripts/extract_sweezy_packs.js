#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function decodeHtmlEntities(input) {
  return input
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function slugify(input) {
  return input
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-+/g, '-');
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function collectAssets(cursorConfig) {
  return unique([
    cursorConfig.cursor?.['preview-ext-image'],
    cursorConfig.cursor?.path,
    ...(cursorConfig.cursor?.frames || []),
    cursorConfig.pointer?.['preview-ext-image'],
    cursorConfig.pointer?.path,
  ]);
}

function main() {
  const inputPath = process.argv[2];
  const outputPath = process.argv[3];

  if (!inputPath || !outputPath) {
    console.error('Usage: extract_sweezy_packs.js <input-html> <output-json>');
    process.exit(1);
  }

  const html = fs.readFileSync(inputPath, 'utf8');
  const matches = [...html.matchAll(/data-cursor='([^']+)'/g)];
  const byId = new Map();

  for (const match of matches) {
    const raw = decodeHtmlEntities(match[1]);
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      continue;
    }

    const cursorConfig = parsed && parsed.cursorConfig;
    if (!cursorConfig || byId.has(cursorConfig.id)) {
      continue;
    }

    byId.set(cursorConfig.id, {
      id: cursorConfig.id,
      name: cursorConfig.name,
      slug: slugify(cursorConfig.name),
      isAnimated: Boolean(cursorConfig.isAnimated),
      collection: parsed.collection || null,
      cursorConfig,
      assets: collectAssets(cursorConfig),
    });
  }

  const packs = [...byId.values()].sort((a, b) => a.id - b.id);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify({ count: packs.length, packs }, null, 2));
  console.log(`extracted ${packs.length} packs to ${outputPath}`);
}

main();
