#!/bin/bash
set -euo pipefail

if [[ ! `hub` ]]; then
	echo "you need to install hub (e.g. 'sudo dnf install hub')"
	exit 1
fi

if [[ ! `yq` ]]; then
	echo "you need to install yq (go to 'https://github.com/mikefarah/yq/releases')"
	exit 1
fi

if [[ ! `grepdiff` ]]; then
	echo "you need to install patchdiff (e.g. 'sudo dnf install patchutils')"
	exit 1
fi

tmpdir=$(mktemp -d)
pushd $tmpdir
echo "work dir is $tmpdir"
function cleanup {
	popd
	echo "cleaning up $tmpdir"
	rm -rf $tmpdir
}
trap cleanup EXIT

for component in "$@"; do
	git clone --depth 10 git@github.com:openshift/${component}.git
	pushd ${component}

	hub fork --remote-name contrib
	git checkout -b enhancement/single-node-annotation
	for manifest in $(find manifests/*.yaml); do
		echo "editing $manifest"
		yq write --tag "!!str" -d'*' -i $manifest 'metadata.annotations['include.release.openshift.io/single-node-production-edge']' 'true'
		git diff -U0 -w --no-color | grepdiff -E "single-node-production-edge" --output-matching=hunk | git apply --cached --ignore-whitespace --unidiff-zero -
	done

	git commit -m "MGMT-3105: add single-node annotations to CVO manifests" -m "this matches openshift/enhancements#504 and doesn't change existing behavior"
	git reset --hard
	git push contrib enhancement/single-node-annotation
	hub pull-request --no-edit --push

	popd
done
