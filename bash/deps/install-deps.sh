#!/usr/bin/env bash
set -e

. ./utils.sh
MIT="$(remove_non_alpha "$(to_lower "$(clean_license_text 'Permission is hereby granted, free of charge, to any person obtaining a copy of ')")")"
ISC="$(remove_non_alpha "$(to_lower "$(clean_license_text 'Permission to use, copy, modify, and/or distribute this software for any purpose ')")")"
BSD="$(remove_non_alpha "$(to_lower "$(clean_license_text 'Redistribution and use in source and binary forms, with or without modification')")")"
CC0="$(remove_non_alpha "$(to_lower "$(clean_license_text 'Copyright and related rights for sample code are waived via CC0.')")")"
CCPL="$(remove_non_alpha "$(to_lower "$(clean_license_text 'THE WORK (AS DEFINED BELOW) IS PROVIDED UNDER THE TERMS OF THIS CREATIVE COMMONS PUBLIC LICENSE ("CCPL" OR "LICENSE").')")")"
APACHE='http://www.apache.org/licenses/LICENSE-2.0'


declare -A PY_LICENSE_INFO
declare -A PY_LICENSES
declare -A JS_LICENSE_INFO
declare -A JS_LICENSES
declare -A GO_LICENSE_INFO
declare -A GO_LICENSES
declare -A MVN_LICENSE_INFO
declare -A MVN_LICENSES

declare OUTPUT=${OUTPUT:-/tmp/licenses.csv}
echo "language,library,license,license_text" > ${OUTPUT}

function get_license_type () {
	local cmp="$(remove_non_alpha "$(to_lower "${1}")")"

	echo -e $cmp
	echo '-------'
	echo  -e $MIT
	if [[ "${cmp}" == *"$MIT"* ]]; then
		echo "MIT"
  elif [[ "${cmp}" == *"$ISC"* ]]; then
		echo "ISC"
  elif [[ "${cmp}" == *"$BSD"* ]]; then
		echo "BSD"
  elif [[ "${cmp}" == *"$CC0"* ]]; then
		echo "CC0"
  elif [[ "${cmp}" == *"$CCPL"* ]]; then
		echo "CCPL"
  elif [[ "${cmp}" == *"$APACHE"* ]]; then
		echo "APACHE"
	else
		echo "UNKNOWN"
	fi
}

function build_py () {
	echo "Processing python project: $1"
	local l
	while read l; do
		if [[ $l =~ ([a-zA-Z0-9_-]+).* ]]; then
			local pkg="${BASH_REMATCH[1]}"
			if [ ${PY_LICENSE_INFO[$pkg]+_} ]; then continue; fi

			echo "Processing python package: $pkg"

			local resp
			resp=$(curl -L https://pypi.python.org/pypi/$pkg/json/ 2> /dev/null) || {
				continue
			}

			local lic
			lic=$(echo $resp | jq '.info.license') || {
				continue
			}

			local clean
			clean="$(clean_license_text "$lic")" || {
				continue
			}
			if [[ $clean == "" ]]; then
				clean="UNKNOWN"
			fi

			local license licenseType
			if (( $(echo $clean | wc -c) >= 100 )); then
				license="$clean"
				licenseType=$(get_license_type "$clean")
		  else
				license=""
				licenseType="$clean"
			fi

			PY_LICENSE_INFO[$pkg]=$licenseType
			PY_LICENSES[$pkg]=$license
		fi
	done < $1/requirements.txt
}

function build_js () {
	echo "Processing js project: $1"

	for d in $(ls -p $1/node_modules/ | grep ".*\/$"); do
		if [[ -e $1/node_modules/$d/package.json ]]; then
			cat $1/node_modules/$d/package.json | jq '.license'
		fi
	done
}

function main () {
	local d
	for d in $(ls -p . | grep ".*\/$"); do
		local name=$(python -c "print('$d'.strip('/'))")
		if [[ ${BUILD_ONLY} != $name && ${BUILD_ONLY} != "" ]]; then
			continue
		fi
		if [[ "$name" == "dotfiles" ]]; then
			continue
		fi

		if [[ "${START}" != "" && "${START}" > "$name" ]]; then
			continue
		fi

		if [ -e "$name/requirements.txt" ]; then
			echo "$name is python"
			if [[ "${TTYPE}" != "py" && ${TTYPE} != "" ]]; then
				continue
			fi
			if [[ "${BUILD:-true}" == "true" ]]; then
				build_py $name
			fi
		elif [ -e "$name/glide.yaml" ]; then
			echo "$name is go"
			if [[ "${TTYPE}" != "go" && ${TTYPE} != "" ]]; then
				continue
			fi
			if [[ "${INSTALL:-true}" == "true" ]]; then
				glide update
			fi
			if [[ "${BUILD:-true}" == "true" ]]; then
				build_go $name
			fi
		elif [ -e "$name/package.json" ]; then
			echo "$name is js"
			if [[ "${TTYPE}" != "js" && ${TTYPE} != "" ]]; then
				continue
			fi
			if [[ "${INSTALL:-true}" == "true" ]]; then
				yarn install
			fi
			if [[ "${BUILD:-true}" == "true" ]]; then
				build_js $name
			fi
		elif [ -e "$name/pom.xml" ]; then
			echo "$name is maven"
			if [[ "${TTYPE}" != "mvn" && ${TTYPE} != "" ]]; then
				continue
			fi
			if [[ "${INSTALL:-true}" == "true" ]]; then
				mvn install -Dmaven.test.skip=true
			fi
		else
			echo "$name is UNKNOWN"
			exit 1
		fi
	done

	if [[ "${TTYPE}" == "mvn" || ${TTYPE} == "" ]]; then
		if [[ "${BUILD:-true}" == "true" ]]; then
			build_mvn
		fi
	fi


	local pkg
	local licenseType
	local license
	if [[ "${TTYPE}" == "py" || ${TTYPE} == "" ]]; then
		for pkg in "${!PY_LICENSE_INFO[@]}"; do 
			echo "Writing package $pkg"
			licenseType="${PY_LICENSE_INFO[$pkg]}"
			license="${PY_LICENSES[$pkg]}"
			echo "python,$pkg,\"$licenseType\",\"$license\"" >> "${OUTPUT}"
		done
	fi
}

# main

get_license_type "$(pbpaste)"

echo "Done"