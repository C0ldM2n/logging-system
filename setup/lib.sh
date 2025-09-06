#!/usr/bin/env bash

es_ca_cert="${BASH_SOURCE[0]%/*}"/ca.crt

# Log a message.
log () {
	echo "[+] $1"
}

# Log a message at a sub-level.
sublog () {
	echo "   ⠿ $1"
}

# Log an error.
err () {
	echo "[x] $1" >&2
}

# Log an error at a sub-level.
suberr () {
	echo "   ⠍ $1" >&2
}

# Poll the 'elasticsearch' service until it responds with HTTP code 200.
wait_for_elasticsearch () {

	# local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}' "${ES_URL}/"
	# 	"--resolve" "${ES_HOST}:9200${ES_PORT}ES_HOST}" "--cacert" "$es_ca_cert"
	# 	)

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}' "${ES_URL}/"
		'--cacert' "$es_ca_cert" )

	if [[ -n "${ES_PASSWORD}" ]]; then
		args+=( '-u' "elastic:${ES_PASSWORD}" )
	fi

	local -i result=1
	local output

	# retry for max 300s (60*5s)
	for _ in $(seq 1 60); do
		local -i exit_code=0
		output="$(curl "${args[@]}")" || exit_code=$?

		if ((exit_code)); then
			result=$exit_code
		fi

		# if [[ "${output: -3}" -eq 200 ]]; then
		if [[ "${output: -3}" == 200 ]]; then
			result=0
			break
		fi

		sleep 5
	done

	if ((result)) && [[ "${output: -3}" -ne 000 ]]; then
		echo -e "\n${output::-3}"
	fi

	return $result
}

# Poll the Elasticsearch users API until it returns users.
wait_for_builtin_users () {

	# local -a args=( '-s' '-D-' '-m15' "${ES_URL}/_security/user?pretty"
	# 	"--resolve" "${ES_HOST}:9200:${ES_HOST}" "--cacert" "$es_ca_cert"
	# 	)

	local -a args=( '-s' '-D-' '-m15' "${ES_URL}/_security/user?pretty"
		'--cacert' "$es_ca_cert" )

	if [[ -n "${ES_PASSWORD}" ]]; then
		args+=( '-u' "elastic:${ES_PASSWORD}" )
	fi

	local -i result=1

	local line
	local -i exit_code
	local -i num_users

	# retry for max 30s (30*1s)
	for _ in $(seq 1 30); do
		num_users=0

		# read exits with a non-zero code if the last read input doesn't end
		# with a newline character. The printf without newline that follows the
		# curl command ensures that the final input not only contains curl's
		# exit code, but causes read to fail so we can capture the return value.
		# Ref. https://unix.stackexchange.com/a/176703/152409
		while IFS= read -r line || ! exit_code="$line"; do
			if [[ "$line" =~ _reserved.+true ]]; then
				(( num_users++ ))
			fi
		done < <(curl "${args[@]}"; printf '%s' "$?")

		if ((exit_code)); then
			result=$exit_code
		fi

		# we expect more than just the 'elastic' user in the result
		if (( num_users > 1 )); then
			result=0
			break
		fi

		sleep 1
	done

	return $result
}

# Verify that the given Elasticsearch user exists.
check_user_exists () {

	local username=$1

	# local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
	# 	"${ES_URL}/_security/user/${username}"
	# 	"--resolve" "${ES_HOST}:${ES_PORT}:${ES_HOST}" "--cacert" "$es_ca_cert"
	# 	)

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"${ES_URL}/_security/user/${username}"
		'--cacert' "$es_ca_cert" )

	if [[ -n "${ES_PASSWORD}" ]]; then
		args+=( '-u' "elastic:${ES_PASSWORD}" )
	fi

	local -i result=1
	local -i exists=0
	local output

	output="$(curl "${args[@]}")"
	# if [[ "${output: -3}" -eq 200 || "${output: -3}" -eq 404 ]]; then
	if [[ "${output: -3}" == 200 || "${output: -3}" == 404 ]]; then
		result=0
	fi
	# if [[ "${output: -3}" -eq 200 ]]; then
	if [[ "${output: -3}" == 200 ]]; then
		exists=1
	fi

	if ((result)); then
		echo -e "\n${output::-3}"
	else
		echo "$exists"
	fi

	return $result
}

# Set password of a given Elasticsearch user.
set_user_password () {
	local username=$1
	local password=$2


	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"${ES_URL}/_security/user/${username}/_password"
		# "--resolve" "${ES_HOST}:9200:${ES_HOST}" "--cacert" "$es_ca_cert"
		"--cacert" "$es_ca_cert"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"password\" : \"${password}\"}" )

	if [[ -n "${ES_PASSWORD}" ]]; then
		args+=( '-u' "elastic:${ES_PASSWORD}" )
	fi

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	# if [[ "${output: -3}" -eq 200 ]]; then
	if [[ "${output: -3}" == 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Create the given Elasticsearch user.
create_user () {
	local username=$1
	local password=$2
	local role=$3

	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"${ES_URL}/_security/user/${username}"
		# "--resolve" "${ES_HOST}:${ES_PORT}:${ES_HOST}" "--cacert" "$es_ca_cert"
		'--cacert' "$es_ca_cert"
		'-X' 'POST'
		'-H' 'Content-Type: application/json'
		'-d' "{\"password\":\"${password}\",\"roles\":[\"${role}\"]}"
		)

	if [[ -n "${ES_PASSWORD}" ]]; then
		args+=( '-u' "elastic:${ES_PASSWORD}" )
	fi

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	# if [[ "${output: -3}" -eq 200 ]]; then
	if [[ "${output: -3}" == 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}

# Ensure that the given Elasticsearch role is up-to-date, create it if required.
ensure_role () {
	local name=$1
	local body=$2


	local -a args=( '-s' '-D-' '-m15' '-w' '%{http_code}'
		"${ES_URL}/_security/role/${name}"
		# "--resolve" "${ES_HOST}:9200:${ES_HOST}" "--cacert" "$es_ca_cert"
		# '-X' 'POST'
		'--cacert' "$es_ca_cert"
		'-X' 'PUT'
		'-H' 'Content-Type: application/json'
		'-d' "$body"
		)

	if [[ -n "${ES_PASSWORD}" ]]; then
		args+=( '-u' "elastic:${ES_PASSWORD}" )
	fi

	local -i result=1
	local output

	output="$(curl "${args[@]}")"
	if [[ "${output: -3}" == 200 ]]; then
		result=0
	fi

	if ((result)); then
		echo -e "\n${output::-3}\n"
	fi

	return $result
}


es_api() {
	# usage: es_api METHOD PATH [@file | -d json]
	local method="$1"; shift
	local path="$1"; shift
	curl -sS -k -u "elastic:${ES_PASSWORD}" \
		-H 'Content-Type: application/json' \
		--cacert "$es_ca_cert" \
		-X "$method" "${ES_URL}${path}" "$@"
}

ensure_ilm_policy_from_file() {
	local name="$1"
	local file="$2"
	sublog "Ensuring ILM policy '${name}'"
	es_api PUT "/_ilm/policy/${name}" @"${file}" >/dev/null
	sublog "ILM policy '${name}' ensured"
	}

ensure_index_template_from_file() {
	local name="$1"
	local file="$2"
	sublog "Ensuring index template '${name}'"
	es_api PUT "/_index_template/${name}" @"${file}" >/dev/null
	sublog "Index template '${name}' ensured"
}
