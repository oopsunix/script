#!/usr/bin/env bash

## Usage: curl -fsSL https://raw.githubusercontent.com/oopsunix/script/main/test/docker_hub_speed_test.sh | bash
## Modify: oopsunix
## Author: lework
## Function: Docker Hub mirror site speed test.


######################################################################################################
# environment configuration
######################################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

image_name="library/centos"
image_tag="latest"

declare -A mirrors
mirrors=(
  [azure]="http://dockerhub.azk8s.cn"
  [tencent]="https://ccr.ccs.tencentyun.com"
  [daocloud]="https://docker.m.daocloud.io"
  [dockerpull.com]="https://dockerpull.com"
  [dockerproxy.com]="https://dockerproxy.com"
  [dockerproxy.cn]="https://dockerproxy.cn"
)

######################################################################################################
# function
######################################################################################################

function shutdown() {
  tput cnorm # reset cursor
}


function error() {
  ps -ef | grep "$0" | awk '{print $2}' | xargs kill -9 '{}' >/dev/null 2>&1
}

trap shutdown EXIT
trap error ERR 2 3


function spinner() {
  # make sure we use non-unicode character type locale
  # (that way it works for any locale as long as the font supports the characters)
  local LC_CTYPE=C
  speed_test "$@" &
  sleep 1

  local pid=$(ps -ef | grep -E '[w]get.*-4O /dev/null -T300' | awk '{print $2}') # Process Id of the previous running command

  local spin='-\|/'
  local charwidth=1

  local i=0
  tput civis # cursor invisible
  while kill -0 $pid 2>/dev/null; do
    local i=$(((i + $charwidth) % ${#spin}))
    printf "%s" "${spin:$i:$charwidth}"

    echo -en "\033[1D"
    sleep .1
  done
  tput cnorm
  wait
}

speed_test() {
    local output=$(LANG=C wget ${3:+"--header="}"$3" -4O /dev/null -T300 "$1" 2>&1)
    local speed=$(printf '%s' "$output" | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}')
    local ipaddress=$(printf '%s' "$output" | awk -F'|' '/Connecting to .*\|([^\|]+)\|/ {print $2}'| tail -1)
    local time=$(printf '%s' "$output" | awk -F= '/100% / {print $2}')
    local size=$(printf '%s' "$output" | awk '/Length:/ {s=$3} END {gsub(/\(|\)/,"",s); print s}')

    # 使用curl查询IP地址信息
    if [ -n "$ipaddress" ]; then
      local ipinfo=$(curl -s "http://ip-api.com/json/$ipaddress?fields=countryCode,asname")
      if [ $? -eq 0 ]; then
        local country=$(echo $ipinfo | jq -r '.countryCode')
        local asname=$(echo $ipinfo | jq -r '.asname')
        ipasn="$country $asname"
      fi
    else
     ipasn=""
    fi
    printf "${YELLOW}%-30s${GREEN}%-20s${BLUE}%-14s${BLUE}%-20s${PLAIN}%-20s${RED}%-14s${PLAIN}\n" "$2" "${ipaddress}" "${ipasn}" "${size}" "${time}" "${speed}"
}


######################################################################################################
# main
######################################################################################################

if  [ ! -e '/usr/bin/wget' ]; then
    echo "Error: wget command not found. You must be install wget command at first."
    exit 1
fi

if  [ ! -e '/usr/bin/curl' ]; then
    echo "Error: curl command not found. You must be install curl command at first."
    exit 1
fi

if  [ ! -e '/usr/bin/jq' ]; then
    echo "Error: jq command not found. You must be install jq command at first."
    exit 1
fi

clear
echo -e "\n\nDocker Hub mirror site speed test"

echo -e "\n[Mirror Site]"
for mirror in ${!mirrors[*]}; do
  printf "${PLAIN}%-30s${GREEN}%-20s${PLAIN}\n" ${mirror} ":  ${mirrors[$mirror]}"
done
printf "${PLAIN}%-30s${GREEN}%-20s${PLAIN}\n" "docker" ":  https://registry-1.docker.io"

echo -e "\n[Test]"
echo -e "Test Image        : ${YELLOW}${image_name}:${image_tag}${PLAIN}"

docker_token=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${image_name}:pull"  | awk '-F"' '{print $4}')
image_manifests=$(curl -fsSL -H "Authorization: Bearer ${docker_token}" "https://registry-1.docker.io/v2/${image_name}/manifests/${image_tag}" | awk -F'"' '/"blobSum":/ {print $4}')
image_layer=$(echo $image_manifests | tr ' ' '\n' | sort -u| head -1)
echo -e "Download layer    : ${YELLOW}${image_layer}${PLAIN}\n"

printf "%-30s%-20s%-14s%-20s%-20s%-14s\n" "Site Name" "IPv4 address" "IP ASN Org" "File Size" "Download Time" "Download Speed"
for mirror in ${!mirrors[*]}; do
  if [ "${#image_layer}" == "0" ]; then
    image_manifests=$(curl -s "${mirror}/v2/library/${image_name}/manifests/${image_tag}" | awk -F'"' '/"blobSum":/ {print $4}')
    image_layer=$( echo $resp | tr ' ' '\n' | sort -u | head -1)
  fi
  spinner "${mirrors[$mirror]}/v2/${image_name}/blobs/${image_layer}" ${mirror} "Authorization: Bearer $docker_token"
done

# 修复部分公益镜像源需要token
spinner "https://registry-1.docker.io/v2/${image_name}/blobs/${image_layer}" "docker" "Authorization: Bearer $docker_token"
echo
