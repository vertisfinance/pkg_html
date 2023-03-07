#!/bin/bash

function pip_json() {
    test -z "$EXPORT_DIR" && return 1
    WD="$EXPORT_DIR"
    REQ_FILE="/tmp/requirements_noversion.txt"
    INSPECT_OUTPUT="$WD/pip-inspect.json"
    UPGRADE_OUTPUT="$WD/pip-upgrade.json"
    MERGED_OUTPUT="$WD/pip.json"

    # get installed packages JSON
    pip inspect > "$INSPECT_OUTPUT"

    # select manually installed packages and
    # create a requirements file without versions
    JQ_QUERY=(
	'.installed | map(select(.requested))'
	'| map(.metadata.name) | join("\n")'
    )
    jq -r "${JQ_QUERY[*]}" "$INSPECT_OUTPUT" > "$REQ_FILE"

    # get upgraded packages JSON
    pip install --dry-run --ignore-installed \
	--report "$UPGRADE_OUTPUT" -r "$REQ_FILE"

    # merge two files and transform arrays to objects
    JQ_FILTER='map({key: .metadata.name, value: .}) | from_entries'
    JQ_QUERY_MERGE=(
	'{installed: .[0].installed |'
	"$JQ_FILTER"
	', upgrade: .[1].install |'
	"$JQ_FILTER"
	'}'
    )
    jq --slurp "${JQ_QUERY_MERGE[*]}" \
       "$INSPECT_OUTPUT" "$UPGRADE_OUTPUT" > "$MERGED_OUTPUT"
}

function npm_json() {
    # exit if no npm installed or no project dir defined
    which npm >/dev/null || ERROR="npm is not installed"
    test -z "$EXPORT_DIR" && ERROR="EXPORT_DIR is not defined"
    if test ! -z "$ERROR"; then
	echo "$ERROR"
	return 1
    fi
    test -z "$NPM_PROJECT_DIR" && cd "$START_DIR" || cd "$NPM_PROJECT_DIR"
    echo "npm project dir: $PWD"

    WD="$EXPORT_DIR"
    INSPECT_JSON="$WD/npm-inspect.json"
    INSTALLED_JSON="$WD/npm-installed.json"
    DETAILS_JSON="$WD/npm-details.json"
    DATA_JSON="$WD/npm.json"

    # save list of packages, return if no packages
    npm ls --json > "$INSPECT_JSON"
    test `head -1 $INSPECT_JSON` == '{}' && return 1
    
    JQ_QUERY=(
	'.dependencies | to_entries'
	'| map({key: .key|sub("^.*/"; ""), value: .value.version})'
	'| from_entries'
    )
    jq "${JQ_QUERY[*]}" "$INSPECT_JSON" > "$INSTALLED_JSON"
    PKG_LIST=( $( jq -r '.|keys|join(" ")' "$INSTALLED_JSON" ) )

    # reset and fill details.json
    echo -n '' > "$DETAILS_JSON"
    for PKG in "${PKG_LIST[@]}"; do
	echo "... fetching details of package $PKG"
	npm view --json "$PKG" >> "$DETAILS_JSON"
    done

    # merge data
    JQ_QUERY_MERGE=(
	'. | {packages: map({'
	'key: .name,'
	'value: {installed_version: $installed[0][.name], details: .}'
	'}) | from_entries}'
    )
    jq "${JQ_QUERY_MERGE[*]}" \
       -s "$DETAILS_JSON" \
       --slurpfile installed "$INSTALLED_JSON" > "$DATA_JSON"
}

# BEGIN
HELP_MSG=$( cat <<EOF
$0: export pip and/or npm package info to html

Available options:
  --export-dir=</path/to/export>		: directory to save JSON data (default=/tmp/export)
  --html-dir=<path/to/html>			: directory to save HTML files (default=export-dir)
  --npm						: inspect npm packages
  --npm-project-dir=</path/to/npm/project>	: default=\$PWD (activates npm)
  --pip						: inspect pip packages
  --pip-venv=</path/to/virtualenv>		: inspect pip packages in virtualenv,
  						  if not activated one already (optional, activates pip)
  --help, -h, ?					: display this help
\n
EOF
	)

# getting script directory
START_DIR="$PWD"
SCRIPT_PATH=$(readlink -f "$BASH_SOURCE")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
cd "$SCRIPT_DIR"

# checking renderer
RENDERER="$SCRIPT_DIR/renderer.py"
test -f "$RENDERER" || exit 1

# parsing arguments
test -z $1 && echo -e "${HELP_MSG}" && exit 0
while test ! -z $1 ; do
    case $1 in
	--export-dir=*)
	    EXPORT_DIR=`echo $1 | cut -d '=' -f 2`
	    ;;
	--html-dir=*)
	    HTML_DIR=`echo $1 | cut -d '=' -f 2`
	    ;;
	--pip)
	    PIP=pip
	    ;;
	--npm)
	    NPM=npm
	    ;;
	--npm-project-dir=*)
	    NPM=npm
	    NPM_PROJECT_DIR=`echo $1 | cut -d '=' -f 2`
	    ;;
	--pip-venv=*)
	    PIP=pip
	    PIP_VENV=`echo $1 | cut -d '=' -f 2`
	    test -z "$VIRTUAL_ENV" && test -d "$PIP_VENV" && source "$PIP_VENV/bin/activate"
	    ;;
	--help|-h|\?)
	    echo -e "${HELP_MSG}"
	    exit 0
	    ;;
    esac
    shift
done

test -z "$EXPORT_DIR" && EXPORT_DIR="/tmp/export"
test -z "$HTML_DIR" && HTML_DIR="$EXPORT_DIR"

# checking os packages
REQUIRED=( python3 jq )
for PKG in "${REQUIRED[@]}"; do
    which "${PKG}" >/dev/null || MISSING="${PKG} ${MISSING}"
done
if test ! -z "$MISSING"; then
    echo "Missing packages: $MISSING"
    exit 1
fi

# ensure required pip packages are installed
which pip >/dev/null && pip install --upgrade pip || python3 -m pip install pip
pip show -q jinja2 || pip install jinja2

# ensure export directory is ready
test -d "$EXPORT_DIR" || mkdir "$EXPORT_DIR"
echo "Export directory: ${EXPORT_DIR}"

# calling data collector function and rendering HTML file
for TYPE in $PIP $NPM; do
    echo "... exporting $TYPE packages to JSON"
    MSG="Export successful!"
    ${TYPE}_json && \
	python3 "${RENDERER}" \
	    --type=${TYPE} \
	    "--in=${EXPORT_DIR}/${TYPE}.json" \
	    "--out=${HTML_DIR}/${TYPE}.html" || MSG="Export failed!"
    echo "$MSG"
done

exit 0
