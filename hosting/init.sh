#!/usr/bin/env bash

# Download the set of scripts needed for the automated hosting setup.
# Make the script executable with `chmod +x init.sh` and run it with `./init.sh`.
# Begin here and after the scripts are downloaded, execute `./hosting/main.sh` to start the setup.

rm -rf hosting/
git clone --filter=blob:none --sparse https://github.com/luckynumb3rs/stremio-perfect-setup.git temp-repo
cd temp-repo
git sparse-checkout set hosting
cd ..
cp -r temp-repo/hosting ./hosting
rm -rf temp-repo