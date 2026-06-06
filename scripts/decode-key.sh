#!/usr/bin/env bash
# decode-key.sh - Decode an encoded key for verification
# Usage: scripts/decode-key.sh <passphrase> <encoded-value>

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <passphrase> <encoded-value>" >&2
  exit 1
fi

passphrase=$1
encoded=$2

node - "$passphrase" "$encoded" <<'NODE'
const crypto = require('node:crypto');

const [, , passphrase, encoded] = process.argv;

try {
  const payload = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));

  const salt = Buffer.from(payload.s, 'base64');
  const iv = Buffer.from(payload.n, 'base64');
  const iterations = payload.i;
  const ciphertext = Buffer.from(payload.c, 'base64');

  const key = crypto.pbkdf2Sync(passphrase, salt, iterations, 32, 'sha256');

  // Split ciphertext and auth tag
  const encrypted = ciphertext.slice(0, -16);
  const tag = ciphertext.slice(-16);

  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);

  const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);

  process.stdout.write(decrypted.toString('utf8'));
  process.stdout.write('\n');
} catch (err) {
  process.stderr.write(`Decryption failed: ${err.message}\n`);
  process.exit(1);
}
NODE
