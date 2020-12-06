#!/bin/bash
set -eo pipefail

description="add 'single-node-production-edge' annotations to CVO manifests.

This adds annotations for the single-node-production-edge cluster profile. There's a growing requirement from several customers to enable creation of single-node (not high-available) Openshift clusters.
In stage one (following openshift/enhancements#504) there should be no implication on components logic.
In the next stage, the component's behavior will match a non high-availability profile if the customer is specifically interested in one.
This PR is separate from the 'single-node-developer' work, which will implement a different behavior and is currently on another stage of implementation.

For more info, please refer to the enhancement link and participate in the discussion."

echo "${description}"

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
edit=0
for arg in "$@"; do
	case $arg in
		-d | --dry-run)
		dry_run=1
		;;

		-e | --edit)
		edit=1
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
	git clone git@github.com:openshift/${component}.git
	pushd ${component}

	if [[ "$dry_run" == 1 ]]; then
		echo "checking if there's an existing open PR..."
		previous_pr=$(hub pr list --state open -f "%U %t%n" | grep "add 'single-node-production-edge'" | cut -d " " -f 1 || true)
		if [[ "$previous_pr" ]]; then
			echo "ignoring. A previous PR is already open: ${previous_pr}"
			continue
		fi
		echo "no existing PR have been found"
	fi

	hub fork --remote-name contrib
	git checkout -b enhancement/single-node-annotation

	readarray -d '' manifests < <(find -name "*.yaml" -not -path "./examples/*" -not -path "./vendor/*" -not -path "./bindata/*" -not -path "./assets/*" -print0)
	if [[ -z "$manifests" ]]; then
		echo "no manifests have been found"
		continue
	fi

	for manifest in "${manifests[@]}"; do
		yq write --tag "!!str" -d'*' -i "$manifest" 'metadata.annotations['include.release.openshift.io/single-node-production-edge']' 'true'
		git diff -U0 -w --no-color | grepdiff "single-node-production-edge" --output-matching=hunk | git apply --cached --ignore-whitespace --unidiff-zero -
	done

	git stash --keep-index

	if [[ "$edit" == 1 ]]; then
		git reset
		git add -p .
	fi

	echo "$description" | git commit -F-

	if [[ "$verbose" > 0 ]]; then
		echo "-----------------------"
		echo "The applied commit:"
		echo "-----------------------"
		git --no-pager show --pretty="" --name-only
		git --no-pager show --pretty=fuller
		echo "-----------------------"
	fi


	if [[ "$dry_run" == 0 ]]; then
		git push contrib enhancement/single-node-annotation
		hub pull-request --no-edit --push
	fi

	popd
done
