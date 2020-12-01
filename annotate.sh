#!/bin/bash
set -eo pipefail

if [[ ! `hub` ]]; then
	echo "you need to install hub (e.g. 'sudo dnf install hub')"
	exit 1
fi

if [[ ! `yq` ]]; then
	echo "you need to install yq (go to 'https://github.com/mikefarah/yq/releases')"
	exit 1
fi

if [[ ! `grepdiff --version` ]]; then
	echo "you need to install patchdiff (e.g. 'sudo dnf install patchutils')"
	exit 1
fi

components=()
verbose=0
dry_run=0
for arg in "$@"; do
	case $arg in
		-d)
		dry_run=1
		;;

		-v)
		verbose=1
		;;

		-vv)
		verbose=2
		;;

		*)    # component
		components+=($arg)
		;;
	esac
done

if [[ "$verbose" > 1 ]]; then
	set -x
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

for component in "${components[@]}"; do
	git clone --depth 10 git@github.com:openshift/${component}.git
	pushd ${component}

	echo "checking if there's an existing open PR..."
	previous_pr=$(hub pr list --state open -f "%U %t%n" | grep "add 'single-node-production-edge'" | cut -d " " -f 1 || true)
	if [[ "$previous_pr" ]]; then
		echo "ignoring. A previous PR is already open: ${previous_pr}"
		continue
	fi
	echo "no existing PR have been found"

	hub fork --remote-name contrib
	git checkout -b enhancement/single-node-annotation

	readarray -d '' manifests < <(find -wholename "./manifests/*.yaml" -print0)
	#manifests=$(find . -wholename "./manifests/*.yaml" | tr "\n" "\t")
	if [[ -z "$manifests" ]]; then
		echo "no manifests have been found"
		continue
	fi

	for manifest in "${manifests[@]}"; do
		yq write --tag "!!str" -d'*' -i "$manifest" 'metadata.annotations['include.release.openshift.io/single-node-production-edge']' 'true'
		git diff -U0 -w --no-color | grepdiff -E "single-node-production-edge" --output-matching=hunk | git apply --cached --ignore-whitespace --unidiff-zero -
	done

	git commit -m "MGMT-3105: add 'single-node-production-edge' annotations to CVO manifests" -m "this matches openshift/enhancements#504 and doesn't change existing behavior"

	if [[ "$verbose" > 0 ]]; then
		echo "-----------------------"
		echo "The applied commit:"
		echo "-----------------------"
		git --no-pager show
		echo "-----------------------"
	fi

	git reset --hard

	if [[ "$dry_run" == 0 ]]; then
		git push contrib enhancement/single-node-annotation
		hub pull-request --no-edit --push
	fi

	popd
done
