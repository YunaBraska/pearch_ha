#!/bin/sh
set -eu

test "$#" -eq 2

page_config=$1
output=$2
test -f "${page_config}"

output_directory=$(dirname "${output}")
test -d "${output_directory}"
temporary_output=$(mktemp "${output_directory}/pearchha-oauth.XXXXXX")
trap 'rm -f "${temporary_output}"' 0 HUP INT TERM

awk '
function trim(value) {
  sub(/^[[:space:]\r]+/, "", value)
  sub(/[[:space:]\r]+$/, "", value)
  return value
}
function set_value(name, value) {
  if (name == "oauth_client_id") {
    if (++client_id_count != 1 || value == "") {
      exit 1
    }
    client_id = value
  }
  if (name == "oauth_redirect_uri") {
    if (++redirect_uri_count != 1 || value == "") {
      exit 1
    }
    redirect_uri = value
  }
}
/^[[:space:]]*oauth_client_id[[:space:]]*:/ {
  separator = index($0, ":")
  set_value("oauth_client_id", trim(substr($0, separator + 1)))
}
/^[[:space:]]*oauth_redirect_uri[[:space:]]*:/ {
  separator = index($0, ":")
  set_value("oauth_redirect_uri", trim(substr($0, separator + 1)))
}
END {
  if (client_id_count != 1 || redirect_uri_count != 1) {
    exit 1
  }
  printf "PEARCHHA_OAUTH_CLIENT_ID=%s\n", client_id
  printf "PEARCHHA_OAUTH_REDIRECT_URI=%s\n", redirect_uri
}
' "${page_config}" > "${temporary_output}" || {
  printf 'Expected one non-empty oauth_client_id and oauth_redirect_uri in %s.\n' "${page_config}" >&2
  exit 1
}

mv "${temporary_output}" "${output}"
trap - 0 HUP INT TERM
