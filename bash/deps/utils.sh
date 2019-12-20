function quote_csv () {
	echo -e "$1" | sed 's/"/""/g'
}

function trim_whitespace () {
	echo -e $(python -c "print('''$1'''.strip())")
}

function trim_quotes () {
	echo -e $(python -c "print('''$1'''.strip('\"'))")
}

function normalize_whitespace () {
	echo -e "$1" | sed 's/\\n/ /g' | tr -d "\n"
}

function clean_license_text () {
	echo -e "$(quote_csv "$(trim_quotes "$(trim_whitespace "$(normalize_whitespace "$1")")")")"
}
