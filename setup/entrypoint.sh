#!/usr/bin/env bash

set -eu
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

MODE="${MODE:-tls}"	 # tls | setup


case "$MODE" in
	tls)
		# --- tls ---
		declare symbol=⠍

		echo '[+] CA certificate and key'

		if [ ! -f tls/certs/ca/ca.key ]; then
			symbol=⠿

			bin/elasticsearch-certutil ca \
				--silent \
				--pem \
				--out tls/certs/ca.zip

			unzip tls/certs/ca.zip -d tls/certs/ >/dev/null
			rm tls/certs/ca.zip

			echo '   ⠿ Created'
		else
			echo '   ⠍ Already present, skipping'
		fi

		declare ca_fingerprint
		ca_fingerprint="$(openssl x509 -fingerprint -sha256 -noout -in tls/certs/ca/ca.crt \
			| cut -d '=' -f2 \
			| tr -d ':' \
			| tr '[:upper:]' '[:lower:]'
		)"

		echo "   ${symbol} SHA256 fingerprint: ${ca_fingerprint}"

		while IFS= read -r file; do
			echo "   ${symbol}   ${file}"
		done < <(find tls/certs/ca -type f \( -name '*.crt' -or -name '*.key' \) -mindepth 1 -print)

		symbol=⠍

		echo '[+] Server certificates and keys'

		if [ ! -f tls/certs/elasticsearch/elasticsearch.key ]; then
			symbol=⠿

			bin/elasticsearch-certutil cert \
				--silent \
				--pem \
				--in tls/instances.yml \
				--ca-cert tls/certs/ca/ca.crt \
				--ca-key tls/certs/ca/ca.key \
				--out tls/certs/certs.zip

			unzip tls/certs/certs.zip -d tls/certs/ >/dev/null
			rm tls/certs/certs.zip

			find tls -name ca -prune -or -type f -name '*.crt' -exec sh -c 'cat tls/certs/ca/ca.crt >>{}' \;

			# НЕ модифицируем листовые сертификаты.
			# Если нужен fullchain для клиентов — соберём отдельный файл.
			# if [[ -f tls/certs/elasticsearch/elasticsearch.crt ]]; then
			# 	cat tls/certs/elasticsearch/elasticsearch.crt tls/certs/ca/ca.crt \
			# 		> tls/certs/elasticsearch/elasticsearch-fullchain.crt
			# fi

			echo '   ⠿ Created'
		else
			echo '   ⠍ Already present, skipping'
		fi

		while IFS= read -r file; do
			echo "   ${symbol}   ${file}"
		done < <(find tls -name ca -prune -or -type f \( -name '*.crt' -or -name '*.key' \) -mindepth 1 -print)
		;;

	setup)
		# --- setup ---

		declare -A users_passwords
		users_passwords=(
			[otlp_writer]="${OTEL_WRITER_PASSWORD}"
		)

		declare -A users_roles
		users_roles=(
			[otlp_writer]="otel-writer"
		)

		declare -A roles_files
		roles_files=(
			[otel-writer]="otel-writer.json"
		)

		# --------------------------------------------------------

		log 'Waiting for availability of Elasticsearch. This can take several minutes.'

		declare -i exit_code=0
		wait_for_elasticsearch || exit_code=$?

		if ((exit_code)); then
			case $exit_code in
				6)
					suberr 'Could not resolve host. Is Elasticsearch running?'
					;;
				7)
					suberr 'Failed to connect to host. Is Elasticsearch healthy?'
					;;
				28)
					suberr 'Timeout connecting to host. Is Elasticsearch healthy?'
					;;
				*)
					suberr "Connection to Elasticsearch failed. Exit code: ${exit_code}"
					;;
			esac

			exit $exit_code
		fi

		sublog 'Elasticsearch is running'

		log 'Waiting for initialization of built-in users'

		wait_for_builtin_users || exit_code=$?

		if ((exit_code)); then
			suberr 'Timed out waiting for condition'
			exit $exit_code
		fi

		sublog 'Built-in users were initialized'

		for role in "${!roles_files[@]}"; do
			log "Role '$role'"

			declare body_file
			body_file="${SCRIPT_DIR}/roles/${roles_files[$role]:-}"
			if [[ ! -f "${body_file:-}" ]]; then
				sublog "No role body found at '${body_file}', skipping"
				continue
			fi

			sublog 'Creating/updating'
			ensure_role "$role" "$(<"${body_file}")"
		done

		for user in "${!users_passwords[@]}"; do
			log "User '$user'"
			if [[ -z "${users_passwords[$user]:-}" ]]; then
				sublog 'No password defined, skipping'
				continue
			fi

			declare -i user_exists=0
			user_exists="$(check_user_exists "$user")"

			if ((user_exists)); then
				sublog 'User exists, setting password'
				set_user_password "$user" "${users_passwords[$user]}"
			else
				if [[ -z "${users_roles[$user]:-}" ]]; then
					suberr '  No role defined, skipping creation'
					continue
				fi

				sublog 'User does not exist, creating'
				create_user "$user" "${users_passwords[$user]}" "${users_roles[$user]}"
			fi
		done

		# --- ILM policy + Index Template (из файлов) ---
		log 'Installing/Updating ILM policy and index template'

		ILM_FILE="${SCRIPT_DIR}/ilm/otel-logs-policy.json"
		TPL_FILE="${SCRIPT_DIR}/templates/logs-app-template.json"

		if [[ -f "$ILM_FILE" ]]; then
			ensure_ilm_policy_from_file "otel-logs-policy" "$ILM_FILE"
		else
			sublog "ILM file not found: $ILM_FILE (skipping)"
		fi

		if [[ -f "$TPL_FILE" ]]; then
			ensure_index_template_from_file "logs-app-template" "$TPL_FILE"
		else
			sublog "Template file not found: $TPL_FILE (skipping)"
		fi

		sublog 'Setup finished'
		;;

	*)
		echo "Unknown MODE=$MODE (expected tls|setup)" >&2
		exit 2
		;;
esac
