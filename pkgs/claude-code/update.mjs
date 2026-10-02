#!/usr/bin/env node
// Bump the pinned claude-code release.
//
//   node pkgs/claude-code/update.mjs            # follow the `latest` channel
//   node pkgs/claude-code/update.mjs stable     # follow the `stable` channel
//   node pkgs/claude-code/update.mjs 2.1.270    # pin an exact version
//
// Upstream publishes a per-release manifest carrying a hex sha256 for every
// platform, which `fetchurl` accepts verbatim. So a bump is one small JSON file
// and costs two HTTP requests -- no nix-prefetch, no fake-hash round trip, and
// no downloading the ~220 MB binary just to learn its hash.
//
// The manifest served here is the same artifact published as a GitHub release:
// the `claude` binary inside github.com/anthropics/claude-code's
// claude-linux-x64.tar.gz is byte-identical to the one this manifest checksums.
//
// The committed manifest.json is the ONLY integrity anchor for that binary --
// no public substituter carries it (it's unfree, so Hydra never builds it).
// TLS alone only proves *a* server answered; it says nothing about whether the
// bytes are what Anthropic actually published. So before writing a new pin,
// this script verifies upstream's detached PGP signature on manifest.json
// against the Anthropic Claude Code release-signing key committed alongside
// this file (./claude-code-release-signing.asc, fingerprint pinned below),
// using `gpgv` against an explicit keyring built from that committed key --
// never the user's own keyring or trustdb. See verifyManifestSignature() for
// why checking gpgv's exit code alone is not enough.
//
// Signatures are published only for 2.1.89 and later; older releases ship
// manifest.json with no .sig at all, and this script refuses to pin those
// versions rather than silently skip verification for them.
//
// Node is used rather than shell because neither jq nor python3 exists on the
// plain system PATH in this repo's environments. Signature verification needs
// `gpgv` (from gnupg) on PATH too -- see findGpgv() below for what happens
// when it's missing.

import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const BASE = "https://downloads.claude.ai/claude-code-releases";
const OUT = join(HERE, "manifest.json");

// The committed public key. Source: https://downloads.claude.ai/keys/claude-code.asc
// (linked from https://code.claude.com/docs/en/setup, "Binary integrity and
// code signing"). The fingerprint below is published on a *different* host
// (code.claude.com, docs) than the manifest and signature (downloads.claude.ai)
// -- that channel separation is the actual security property: an attacker who
// compromises the download bucket alone still can't also swap the fingerprint
// pinned here.
const PUBKEY_ASC = join(HERE, "claude-code-release-signing.asc");
const PINNED_FINGERPRINT = "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE";

// Manifest signatures are published only from this version onward. Older
// releases have no manifest.json.sig to verify.
const SIG_FLOOR = "2.1.89";

const die = (msg) => {
  console.error(`update.mjs: ${msg}`);
  process.exit(1);
};

const get = async (url) => {
  const res = await fetch(url);
  if (!res.ok) die(`GET ${url} -> HTTP ${res.status}`);
  return res.text();
};

const getBinary = async (url) => {
  const res = await fetch(url);
  if (!res.ok) die(`GET ${url} -> HTTP ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
};

// x.y.z only, matching the regex already enforced on `version` below.
const compareVersions = (a, b) => {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] - pb[i];
  }
  return 0;
};

// Decode an ASCII-armored OpenPGP block into raw binary (the same bytes
// `gpg --dearmor` would produce) using nothing but base64 decoding -- no gpg
// invocation needed just to change format. This keeps `gpgv` the only
// external binary this script depends on.
const decodeArmoredKey = (armored) => {
  const lines = armored.split(/\r?\n/);
  let i = lines.findIndex((l) => l.trim() === "-----BEGIN PGP PUBLIC KEY BLOCK-----");
  if (i === -1) die(`${PUBKEY_ASC} does not look like an ASCII-armored PGP public key block`);
  i++;
  // Skip armor header lines (e.g. "Version: ...") up to the blank separator line.
  while (i < lines.length && lines[i].trim() !== "") i++;
  i++;
  const b64Lines = [];
  while (
    i < lines.length &&
    lines[i].trim() !== "" &&
    !lines[i].startsWith("=") &&
    lines[i].trim() !== "-----END PGP PUBLIC KEY BLOCK-----"
  ) {
    b64Lines.push(lines[i]);
    i++;
  }
  const buf = Buffer.from(b64Lines.join(""), "base64");
  if (buf.length === 0) die(`${PUBKEY_ASC} decoded to zero bytes -- refusing to build an empty keyring`);
  return buf;
};

// gpgv must be reachable on PATH. It is NOT guaranteed to be on the plain
// system PATH in this repo's environments (same constraint as jq/python3).
// Missing gpgv is a hard, loud failure -- never a silent skip -- because a
// verifier that quietly no-ops when its tool is absent reads as protection
// it isn't providing.
const findGpgv = () => {
  const probe = spawnSync("gpgv", ["--version"]);
  if (probe.error?.code === "ENOENT") {
    die(
      "gpgv not found on PATH. Signature verification is required before writing a pin. " +
        "Install gnupg, e.g. `nix shell nixpkgs#gnupg` or `nix-shell -p gnupg`, then re-run " +
        "this script. Refusing to write an unverified pin.",
    );
  }
  if (probe.error) {
    die(`could not run gpgv (${probe.error.message}). Refusing to write an unverified pin.`);
  }
  if (probe.status !== 0) {
    die(`gpgv --version exited ${probe.status}. Refusing to write an unverified pin.`);
  }
};

// Verify `sig` is a detached signature over `data`, made by the pinned key,
// using gpgv against an explicit keyring file built from the committed
// public key -- never the invoking user's own keyring or trustdb.
//
// Checking gpgv's exit code alone is NOT sufficient: gpgv succeeds as long as
// ANY key in the keyring produced a good signature. If this keyring ever grew
// a second key (e.g. a well-meaning future change adding a rotation key),
// exit-code-only verification would silently accept a signature from that new
// key too -- widening trust with no visible change in behavior. Parsing
// --status-fd for the VALIDSIG line and comparing its fingerprint to
// PINNED_FINGERPRINT is what keeps that widening loud instead of silent.
const verifyManifestSignature = ({ keyring, sig, data }) => {
  const dir = mkdtempSync(join(tmpdir(), "claude-code-verify-"));
  try {
    const keyringPath = join(dir, "keyring.gpg");
    const sigPath = join(dir, "manifest.json.sig");
    const dataPath = join(dir, "manifest.json");
    writeFileSync(keyringPath, keyring);
    writeFileSync(sigPath, sig);
    writeFileSync(dataPath, data);

    const result = spawnSync("gpgv", ["--status-fd", "1", "--keyring", keyringPath, sigPath, dataPath], {
      encoding: "utf8",
    });

    const statusLines = (result.stdout ?? "")
      .split("\n")
      .filter((l) => l.startsWith("[GNUPG:] "))
      .map((l) => l.slice("[GNUPG:] ".length));

    if (statusLines.some((l) => l.startsWith("BADSIG"))) {
      die(
        `signature verification FAILED (BADSIG) -- manifest.json does not match its signature. ` +
          `Refusing to write the pin.\n${result.stderr ?? ""}`,
      );
    }
    if (statusLines.some((l) => l.startsWith("EXPSIG") || l.startsWith("EXPKEYSIG") || l.startsWith("REVKEYSIG"))) {
      die(
        `signature verification FAILED (expired or revoked key). Refusing to write the pin.\n${result.stderr ?? ""}`,
      );
    }

    const validsig = statusLines.find((l) => l.startsWith("VALIDSIG "));
    if (result.status !== 0 || !validsig) {
      die(
        `gpgv did not report a valid signature (exit ${result.status}). Refusing to write the pin.\n${result.stderr ?? ""}`,
      );
    }

    // VALIDSIG fields: <fpr> <sig-creation-date> <sig-timestamp> <expire-ts>
    // <sig-version> <reserved> <pubkey-algo> <hash-algo> <sig-class>
    // [<primary-key-fpr>].
    //
    // The FIRST field is whichever key made the signature -- a signing subkey,
    // if upstream ever adopts one. The LAST field is the primary key, which is
    // what we actually pin. Compare the primary, so a future subkey rotation
    // keeps verifying instead of failing closed with a message that reads like
    // an attack. Today upstream signs with the primary key directly (it is
    // [SCE] with no subkeys), so the two fields are identical.
    const sigFields = validsig.split(" ");
    const signingKey = sigFields[1];
    const primaryKey = sigFields.length >= 11 ? sigFields[10] : signingKey;
    if (primaryKey !== PINNED_FINGERPRINT) {
      die(
        `signature is cryptographically valid but its primary key is ${primaryKey} ` +
          `(signature made by ${signingKey}), not the pinned Anthropic release key ` +
          `${PINNED_FINGERPRINT}. Refusing to write the pin -- this could mean the ` +
          `keyring now trusts an unexpected key.`,
      );
    }
    return primaryKey;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

const arg = process.argv[2] ?? "latest";
const version = /^\d+\.\d+\.\d+$/.test(arg)
  ? arg
  : (await get(`${BASE}/${encodeURIComponent(arg)}`)).trim();

if (!/^\d+\.\d+\.\d+$/.test(version)) die(`refusing to pin implausible version ${JSON.stringify(version)}`);

const body = await get(`${BASE}/${version}/manifest.json`);

let manifest;
try {
  manifest = JSON.parse(body);
} catch (e) {
  die(`manifest for ${version} is not valid JSON: ${e.message}`);
}

// Validate before writing, so a malformed response can never land a half-formed
// pin that breaks eval for every host.
if (manifest.version !== version) {
  die(`manifest says version ${manifest.version}, expected ${version}`);
}
const platforms = manifest.platforms ?? {};
for (const required of ["linux-x64", "linux-arm64", "darwin-arm64"]) {
  if (!platforms[required]) die(`manifest for ${version} has no ${required} platform entry`);
}
for (const [name, entry] of Object.entries(platforms)) {
  if (!/^[0-9a-f]{64}$/.test(entry?.checksum ?? "")) {
    die(`platform ${name} has a checksum that is not 64 lowercase hex chars`);
  }
}

if (compareVersions(version, SIG_FLOOR) < 0) {
  die(
    `refusing to pin ${version}: manifest signatures are published only for ${SIG_FLOOR} and later ` +
      `releases, and ${version} predates that floor -- there is no manifest.json.sig to verify it ` +
      `against. Pin ${SIG_FLOOR} or later, or verify this version's provenance out-of-band before ` +
      `overriding.`,
  );
}

if (!existsSync(PUBKEY_ASC)) die(`committed public key not found at ${PUBKEY_ASC}`);
findGpgv();
const keyring = decodeArmoredKey(readFileSync(PUBKEY_ASC, "utf8"));
const sig = await getBinary(`${BASE}/${version}/manifest.json.sig`);
const fingerprint = verifyManifestSignature({ keyring, sig, data: Buffer.from(body, "utf8") });
console.log(`gpgv: good signature on manifest.json for ${version} from pinned key ${fingerprint}`);

const previous = existsSync(OUT) ? JSON.parse(readFileSync(OUT, "utf8")).version : null;
if (previous === version) {
  console.log(`claude-code already pinned at ${version}; nothing to do`);
  process.exit(0);
}

writeFileSync(OUT, body.endsWith("\n") ? body : `${body}\n`);
console.log(`claude-code ${previous ?? "(unpinned)"} -> ${version}`);
