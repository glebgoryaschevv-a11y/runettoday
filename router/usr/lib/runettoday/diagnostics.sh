#!/bin/sh
# Сбор телеметрии роутера OpenWrt.

rt_collect_model() {
	if [ -f /tmp/sysinfo/model ]; then
		cat /tmp/sysinfo/model
	elif [ -f /proc/device-tree/model ]; then
		cat /proc/device-tree/model 2>/dev/null | tr -d '\0'
	else
		echo "OpenWrt Router"
	fi
}

rt_collect_os_version() {
	. /etc/openwrt_release 2>/dev/null
	echo "${DISTRIB_RELEASE:-unknown}"
}

rt_collect_storage() {
	# Возвращает "total used free" в байтах
	set -- $(df -k /overlay 2>/dev/null | tail -1 | awk '{print $2, $3, $4}')
	if [ -z "$1" ]; then
		set -- $(df -k / 2>/dev/null | tail -1 | awk '{print $2, $3, $4}')
	fi
	_total=$((${1:-0} * 1024))
	_used=$((${2:-0} * 1024))
	_free=$((${3:-0} * 1024))
	echo "$_total $_used $_free"
}

rt_collect_memory() {
	# Возвращает "total available" в байтах
	_total=$(awk '/MemTotal/ {print $2*1024}' /proc/meminfo)
	_avail=$(awk '/MemAvailable/ {print $2*1024}' /proc/meminfo)
	[ -z "$_avail" ] && _avail=$(awk '/MemFree/ {print $2*1024}' /proc/meminfo)
	echo "${_total:-0} ${_avail:-0}"
}

rt_collect_network_type() {
	# На роутере всегда ethernet (WAN)
	echo "ethernet"
}

rt_telemetry_json() {
	set -- $(rt_collect_storage)
	_st_total="$1"
	_st_used="$2"
	_st_free="$3"

	set -- $(rt_collect_memory)
	_mem_total="$1"
	_mem_avail="$2"

	_model="$(rt_json_escape "$(rt_collect_model)")"
	_os="$(rt_json_escape "$(rt_collect_os_version)")"
	_net="$(rt_collect_network_type)"

	cat <<JSON
{"model":"$_model","platform":"OpenWrt","osVersion":"$_os","appVersion":"$RT_VERSION","storageTotal":$_st_total,"storageUsed":$_st_used,"storageFree":$_st_free,"memoryTotal":$_mem_total,"memoryAvailable":$_mem_avail,"batteryLevel":null,"batteryState":null,"networkType":"$_net"}
JSON
}
