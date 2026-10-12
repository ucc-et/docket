#!/bin/zsh
# Builds Docket and packages it as a zip and a dmg in dist/.
# Usage: scripts/package.sh [version]
set -e
cd "$(dirname "$0")/.."
VERSION=${1:-0.0.0-dev}
scripts/build.sh $VERSION
rm -rf dist && mkdir dist
ditto -c -k --keepParent build/Docket.app dist/Docket-$VERSION.zip

STAGE=build/dmg && mkdir -p $STAGE
cp -R build/Docket.app $STAGE/
ln -s /Applications $STAGE/Applications
hdiutil create -volname Docket -srcfolder $STAGE -ov -format UDZO dist/Docket-$VERSION.dmg >/dev/null
echo "Packaged:"; ls -1 dist
