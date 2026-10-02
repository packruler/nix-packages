#!/usr/bin/env node
// Bump the pinned Orca release.
//
//   node pkgs/orca-ide/update.mjs            # follow the latest release
//   node pkgs/orca-ide/update.mjs 1.4.218    # pin an exact version
//
// Every Orca release publishes electron-builder's `latest-linux.yml`, which
// carries a base64 sha512 for each Linux artifact. `fetchurl` accepts that
// verbatim as `hash = "sha512-<b64>"`, so a bump is one small JSON file and
// one HTTP request -- no nix-prefetch, no fake-hash round trip, and no
// downloading the ~180 MB deb just to learn its hash.
//
// Unlike claude-code, upstream publishes no signature over this file, so the
// pin is only as trustworthy as GitHub's release hosting.
//
// Node is used rather than shell because neither jq nor python3 exists on the
// plain system PATH in this repo's environments.

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const RELEASES = "https://github.com/stablyai/orca/releases";
const OUT = join(HERE, "manifest.json");

const die = (msg) => {
  console.error(`update.mjs: ${msg}`);
  process.exit(1);
};

const get = async (url) => {
  const res = await fetch(url);
  if (!res.ok) die(`GET ${url} -> HTTP ${res.status}`);
  return res.text();
};

const arg = process.argv[2];
if (arg !== undefined && !/^\d+\.\d+\.\d+$/.test(arg)) die(`expected a version like 1.4.218, got "${arg}"`);

const url = arg ? `${RELEASES}/download/v${arg}/latest-linux.yml` : `${RELEASES}/latest/download/latest-linux.yml`;
const yml = await get(url);

// A line-based read of the few fields needed, rather than a YAML dependency.
// The layout is electron-builder's fixed output:
//   version: 1.4.218
//   files:
//     - url: orca-ide_1.4.218_amd64.deb
//       sha512: <b64>
const version = yml.match(/^version:\s*(\S+)\s*$/m)?.[1];
if (!version || !/^\d+\.\d+\.\d+$/.test(version)) die(`no usable top-level version in ${url}`);
if (arg && version !== arg) die(`asked for ${arg} but ${url} describes ${version}`);

const deb = `orca-ide_${version}_amd64.deb`;
const lines = yml.split(/\r?\n/);
const at = lines.findIndex((l) => l.trim() === `- url: ${deb}`);
if (at === -1) die(`${url} lists no ${deb}`);
const sha512 = lines[at + 1]?.match(/^\s+sha512:\s*(\S+)\s*$/)?.[1];
if (!sha512 || Buffer.from(sha512, "base64").length !== 64) die(`no valid sha512 for ${deb} in ${url}`);

writeFileSync(OUT, `${JSON.stringify({ version, sha512 }, null, 2)}\n`);
console.log(`orca-ide pinned to ${version}`);
