import { mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const designRoot = path.dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(await readFile(path.join(designRoot, "versions.json"), "utf8"));
const version = process.argv[2] || manifest.currentVersion;

if (!manifest.versions.some((item) => item.id === version)) {
  throw new Error(`未知版本 ${version}。可用版本：${manifest.versions.map((item) => item.id).join(", ")}`);
}

const baseURL = process.env.SHOTLENS_DESIGN_URL
  || `http://127.0.0.1:4311/xiaohongshu-product-page/versions/${version}/index.html`;
const outputDir = path.join(designRoot, "versions", version, "exports");

await mkdir(outputDir, { recursive: true });

const executablePath = process.env.PLAYWRIGHT_CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const browser = await chromium.launch({ headless: true, executablePath });
const page = await browser.newPage({ viewport: { width: 1700, height: 1100 }, deviceScaleFactor: 2 });
await page.goto(baseURL, { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);

const boards = page.locator("[data-export]");
for (let index = 0; index < await boards.count(); index += 1) {
  const board = boards.nth(index);
  const name = await board.getAttribute("data-export");
  const format = name.startsWith("00-") ? "-1x1" : /^0[1-9]-/.test(name) ? "-3x4" : "";
  const fileName = `shotlens-xhs-${version}-${name}${format}.png`;
  await board.screenshot({ path: path.join(outputDir, fileName) });
}

await browser.close();
