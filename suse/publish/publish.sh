#!/bin/bash

set -euxo pipefail

: "${AGENT_WORKDIR:=/tmp}"
: "${GPG_KEYNAME:?Required valid gpg keyname}"
: "${BASE:?Require base directory}"
: "${SUSEDIR:? Require where to put binary files}"
: "${SUSE_WEBDIR:? Require where to put repository index and other web contents}"

# $$ Contains current pid
D="$AGENT_WORKDIR/$$"

# Convert string to array to correctly escape cli parameter

function clean(){
  rm -rf $D
}

function generateSite(){

  "$BASE/bin/indexGenerator.py" \
    --distribution opensuse \
    --binaryDir "$SUSEDIR" \
    --targetDir "$SUSE_WEBDIR"
  
  gpg --export -a --output "$D/repodata/repomd.xml.key" "${GPG_KEYNAME}"
  
  "$BASE/bin/branding.py" $D
  
  cp "$SUSE" $D/RPMS/noarch
}

function init(){
  # where to put binary files
  mkdir -p "$SUSEDIR/" # Local

  # shellcheck disable=SC2029
  ssh "$PKGSERVER" "${SSH_OPTS[*]}" mkdir -p "'$SUSEDIR/'" # Remote

  # where to put repository index and other web contents
  mkdir -p "$SUSE_WEBDIR"

  mkdir -p $D/RPMS/noarch $D/repodata
}


function show(){
  echo "Parameters:"
  echo "SUSE: $SUSE"
  echo "SUSEDIR: $SUSEDIR"
  echo "SUSE_WEBDIR: $SUSE_WEBDIR"
  echo "SSH_OPTS: ${SSH_OPTS}"
  echo "PKGSERVER: $PKGSERVER"
  echo "GPG_KEYNAME: $GPG_KEYNAME"
  echo "---"
}

function uploadPackage(){
  rsync -avz "$SUSE" "$SUSEDIR/" # Local
  rsync -avz -e "ssh ${SSH_OPTS}" "${SUSE}" "$PKGSERVER:${SUSEDIR// /\\ }" # Remote
}

function uploadSite(){

  pushd $D
    rsync -avz --exclude RPMS . "$SUSE_WEBDIR/" #Local
    # shellcheck disable=SC2029
    rsync -avz -e "ssh ${SSH_OPTS}" --exclude RPMS . "$PKGSERVER:${SUSE_WEBDIR// /\\ }" # Remote
  
    # generate index on the server
    # server needs 'createrepo' pacakge
    createrepo --update -o "$SUSE_WEBDIR" "$SUSEDIR/" #Local
    # shellcheck disable=SC2029
    ssh "$PKGSERVER"  "${SSH_OPTS}" createrepo --update -o "'$SUSE_WEBDIR'" "'$SUSEDIR/'" # Remote

    scp "${SCP_OPTS}" "$PKGSERVER:${SUSE_WEBDIR// /\\ }/repodata/repomd.xml" repodata/ # Remote
    cp "${SUSE_WEBDIR// /\\ }/repodata/repomd.xml" repodata/ # Local

    gpg \
      --batch \
      --pinentry-mode loopback \
      -u "$GPG_KEYNAME" \
      -a \
      --detach-sign \
      --passphrase-file "$GPG_PASSPHRASE_FILE" \
      --yes \
      repodata/repomd.xml

     scp "${SCP_OPTS}" repodata/repomd.xml.asc "$PKGSERVER:${SUSE_WEBDIR// /\\ }/repodata/"
     cp repodata/repomd.xml.asc "${SUSE_WEBDIR// /\\ }/repodata/"
    
  popd
}

show
init
generateSite
uploadPackage
uploadSite
clean
