#!/usr/bin/env bash

canonical_speech_text() {
  sed -E 's/<#[0-9]+([.][0-9]{1,2})?#>//g' | tr -d '[:space:]'
}

validate_speech_controls() {
  local script_path="$1"
  if grep -Eq '<#[^#]*#>' "$script_path"; then
    while IFS= read -r token; do
      if [[ ! "$token" =~ ^\<\#[0-9]+(\.[0-9]{1,2})?\#\>$ ]]; then
        printf 'speech-controls: invalid pause token: %s\n' "$token" >&2
        return 1
      fi
      local seconds="${token#<#}"
      seconds="${seconds%#>}"
      if ! awk -v value="$seconds" 'BEGIN { exit !(value >= 0.01 && value <= 99.99) }'; then
        printf 'speech-controls: pause outside [0.01, 99.99]: %s\n' "$token" >&2
        return 1
      fi
    done < <(grep -Eo '<#[^#]*#>' "$script_path")
  fi
  if grep -Eq '<#[[:space:]]|[[:space:]]#>' "$script_path"; then
    printf 'speech-controls: pause tokens cannot contain spaces\n' >&2
    return 1
  fi
  if tr '\n' ' ' <"$script_path" | grep -Eq '#>[[:space:]]*<#'; then
    printf 'speech-controls: consecutive pause tokens are not allowed\n' >&2
    return 1
  fi
  local canonical
  canonical="$(canonical_speech_text <"$script_path")"
  if [[ -z "$canonical" || "$canonical" == '<#'* || "$canonical" == *'#>' ]]; then
    printf 'speech-controls: pause tokens must sit between spoken text\n' >&2
    return 1
  fi
}
