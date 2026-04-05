#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function sanitize(input) {
  return input.replace(/[^a-zA-Z0-9._-]+/g, '-');
}

async function ensureDir(dirPath) {
  await fs.promises.mkdir(dirPath, { recursive: true });
}

async function downloadFile(url, destination) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch ${url}: ${response.status} ${response.statusText}`);
  }

  const arrayBuffer = await response.arrayBuffer();
  await fs.promises.writeFile(destination, Buffer.from(arrayBuffer));
}

async function withConcurrency(items, limit, worker) {
  let index = 0;
  const runners = new Array(Math.min(limit, items.length)).fill(null).map(async () => {
    while (index < items.length) {
      const current = items[index++];
      await worker(current);
    }
  });
  await Promise.all(runners);
}

async function main() {
  const manifestPath = process.argv[2];
  const outputDir = process.argv[3];

  if (!manifestPath || !outputDir) {
    console.error('Usage: download_sweezy_assets.js <manifest-json> <output-dir>');
    process.exit(1);
  }

  const manifest = JSON.parse(await fs.promises.readFile(manifestPath, 'utf8'));
  await ensureDir(outputDir);

  const jobs = [];

  for (const pack of manifest.packs) {
    const packDir = path.join(outputDir, `${pack.slug}-${pack.id}`);
    await ensureDir(packDir);
    await fs.promises.writeFile(
      path.join(packDir, 'pack.json'),
      JSON.stringify(pack, null, 2),
    );

    for (const url of pack.assets) {
      const basename = sanitize(path.basename(new URL(url).pathname));
      const destination = path.join(packDir, basename);
      jobs.push({ url, destination, pack: pack.name });
    }
  }

  await withConcurrency(jobs, 6, async (job) => {
    if (fs.existsSync(job.destination)) {
      return;
    }
    await downloadFile(job.url, job.destination);
    console.log(`downloaded ${job.pack}: ${path.basename(job.destination)}`);
  });

  await fs.promises.writeFile(
    path.join(outputDir, 'manifest.json'),
    JSON.stringify(manifest, null, 2),
  );

  console.log(`downloaded ${jobs.length} assets into ${outputDir}`);
}

main().catch((error) => {
  console.error(error.stack || String(error));
  process.exit(1);
});
