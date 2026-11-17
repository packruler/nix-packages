#!/usr/bin/env node
// Bump the pinned Codex CLI release.
//
//   node pkgs/codex/update.mjs            # follow the latest (non-pre) release
//   node pkgs/codex/update.mjs 0.169.0    # pin an exact version
//
// Each release's GitHub API entry carries a sha256 `digest` for every asset,
// and the release also publishes `codex-package_SHA256SUMS`. The pin takes the
// API digest and refuses to write unless SHA256SUMS agrees, so a bump is one
// small JSON file and a few HTTP requests -- no nix-prefetch and no
// downloading ~200 MB bundles just to learn their hashes.
//
// Both values come from GitHub's release hosting, so like orca-ide the pin is
// only as trustworthy as that hosting; upstream publishes no signature over
// SHA256SUMS that this script could check against a committed key.
//
// Node is used rather than shell because neither jq nor python3 exists on the
// plain system PATH in this repo's environments.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const API = "https://api.github.com/repos/openai/codex/releases";
const OUT = join(HERE, "manifest.json");

// Nix system -> upstream target triple. Linux uses the musl builds, which are
// static and need no patchelf.
const TARGETS = {
  "x86_64-linux": "x86_64-unknown-linux-musl",
  "aarch64-linux": "aarch64-unknown-linux-musl",
  "x86_64-darwin": "x86_64-apple-darwin",
  "aarch64-darwin": "aarch64-apple-darwin",
};

const die = (msg) => {
  console.error(`update.mjs: ${msg}`);
  process.exit(1);
};

// GITHUB_TOKEN/GH_TOKEN, when set, lifts the 60/h unauthenticated rate limit.
const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
const get = async (url, accept) => {
  const res = await fetch(url, {
    headers: { ...(accept && { Accept: accept }), ...(token && { Authorization: `Bearer ${token}` }) },
  });
  if (!res.ok) die(`GET ${url} -> HTTP ${res.status}`);
  return res;
};

const arg = process.argv[2];
if (arg !== undefined && !/^\d+\.\d+\.\d+$/.test(arg)) die(`expected a version like 0.169.0, got "${arg}"`);

const release = await (
  await get(arg ? `${API}/tags/rust-v${arg}` : `${API}/latest`, "application/vnd.github+json")
).json();

const version = release.tag_name?.match(/^rust-v(\d+\.\d+\.\d+)$/)?.[1];
if (!version) die(`release tag ${JSON.stringify(release.tag_name)} is not rust-vX.Y.Z`);
if (arg && version !== arg) die(`asked for ${arg} but the release is ${version}`);
if (release.prerelease || release.draft) die(`release ${release.tag_name} is a draft or prerelease`);

const assets = new Map((release.assets ?? []).map((a) => [a.name, a]));

const sumsAsset = assets.get("codex-package_SHA256SUMS");
if (!sumsAsset) die(`release ${release.tag_name} has no codex-package_SHA256SUMS`);
const sums = new Map(
  (await (await get(sumsAsset.url, "application/octet-stream")).text())
    .split("\n")
    .map((l) => l.trim().split(/\s+/))
    .filter((f) => f.length === 2)
    .map(([hash, name]) => [name.replace(/^\*/, ""), hash]),
);

const platforms = {};
for (const [system, target] of Object.entries(TARGETS)) {
  const name = `codex-package-${target}.tar.gz`;
  const digest = assets.get(name)?.digest?.match(/^sha256:([0-9a-f]{64})$/)?.[1];
  if (!digest) die(`release ${release.tag_name} has no sha256 digest for ${name}`);
  if (sums.get(name) !== digest) {
    die(`${name}: API digest ${digest} disagrees with SHA256SUMS ${sums.get(name) ?? "(missing)"}`);
  }
  platforms[system] = { target, sha256: digest };
}

const previous = existsSync(OUT) ? JSON.parse(readFileSync(OUT, "utf8")).version : null;
writeFileSync(OUT, `${JSON.stringify({ version, platforms }, null, 2)}\n`);
console.log(`codex ${previous ?? "(unpinned)"} -> ${version}`);
