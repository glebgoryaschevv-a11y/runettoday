#!/bin/sh

telemetry_collect() {
    python3 - <<'PY'
import json, os, re, subprocess, sys, time

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return ""

def to_int(s, d=0):
    try: return int(s)
    except Exception: return d

def to_float(s, d=0.0):
    try: return float(s)
    except Exception: return d

def get_model():    return run("sysctl -n hw.model") or "Unknown"
def get_os():       return run("sw_vers -productVersion") or "Unknown"
def get_hostname(): return run("hostname") or ""
def get_serial():
    return run("system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/ {print $2}'") or None

def get_cpu():
    brand = run("sysctl -n machdep.cpu.brand_string") or \
            run("system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/ {print $2}'")
    cores = to_int(run("sysctl -n hw.ncpu"))
    loads = re.findall(r'[\d.]+', run("sysctl -n vm.loadavg"))
    l1, l5, l15 = (to_float(loads[0]), to_float(loads[1]), to_float(loads[2])) if len(loads) >= 3 else (0.0, 0.0, 0.0)
    return brand, cores, l1, l5, l15

def get_uptime():
    m = re.search(r'sec = (\d+)', run("sysctl -n kern.boottime"))
    return int(time.time()) - int(m.group(1)) if m else None

def get_storage():
    if os.path.exists("/usr/sbin/diskutil"):
        out = run("/usr/sbin/diskutil info /")
        total = free = 0
        for line in out.splitlines():
            s = line.strip()
            if s.startswith("Container Total Space:"):
                m = re.search(r'\((\d+)\s*Bytes\)', s)
                if m: total = int(m.group(1))
            elif s.startswith("Container Free Space:"):
                m = re.search(r'\((\d+)\s*Bytes\)', s)
                if m: free = int(m.group(1))
        if total > 0:
            return (total, total - free, free)
    p = run("df -k / | tail -1").split()
    if len(p) < 4: return (0, 0, 0)
    return (int(p[1])*1024, int(p[2])*1024, int(p[3])*1024)

def get_memory():
    total = to_int(run("sysctl -n hw.memsize"))
    vm = run("vm_stat")
    ps = 4096
    free = inactive = spec = 0
    for line in vm.splitlines():
        if "page size of" in line:
            m = re.search(r"page size of (\d+)", line)
            if m: ps = int(m.group(1))
        if line.startswith("Pages free:"):        free     = int(line.split()[-1].rstrip('.'))
        elif line.startswith("Pages inactive:"):  inactive = int(line.split()[-1].rstrip('.'))
        elif line.startswith("Pages speculative:"): spec   = int(line.split()[-1].rstrip('.'))
    avail = (free + inactive + spec) * ps
    used = total - avail
    sw = run("sysctl -n vm.swapusage")
    sw_t = sw_u = 0
    mt = re.search(r'total\s*=\s*([\d.]+)M', sw)
    mu = re.search(r'used\s*=\s*([\d.]+)M', sw)
    if mt: sw_t = int(float(mt.group(1)) * 1024 * 1024)
    if mu: sw_u = int(float(mu.group(1)) * 1024 * 1024)
    return total, avail, used, sw_t, sw_u

def get_battery():
    batt = run("pmset -g batt")
    if not batt or "No battery" in batt:
        return (None, None, None, None)
    level = None
    m = re.search(r"(\d+)%", batt)
    if m: level = int(m.group(1))
    state = "unknown"
    if "charging" in batt: state = "charging"
    elif "discharging" in batt: state = "discharging"
    elif "charged" in batt or "full" in batt: state = "full"
    sp = run("system_profiler SPPowerDataType 2>/dev/null")
    cycles = None
    mm = re.search(r'Cycle Count:\s*(\d+)', sp)
    if mm: cycles = int(mm.group(1))
    health = None
    mh = re.search(r'Condition:\s*(.+)', sp)
    if mh: health = mh.group(1).strip()
    return (level, state, cycles, health)

def get_network():
    sp = run("networksetup -listallhardwareports")
    ports, cur = {}, None
    for line in sp.splitlines():
        s = line.strip()
        if s.startswith("Hardware Port:"): cur = s.split(":",1)[1].strip()
        elif s.startswith("Device:") and cur:
            ports[s.split(":",1)[1].strip()] = cur; cur = None
    def kind(p):
        if not p: return "unknown"
        if "Wi-Fi" in p or "AirPort" in p: return "wifi"
        if "Ethernet" in p: return "ethernet"
        return p.lower()
    iface = ""
    for line in run("route -n get default 2>/dev/null").splitlines():
        s = line.strip()
        if s.startswith("interface:"):
            iface = s.split(":",1)[1].strip(); break
    if iface not in ports:
        for d, p in ports.items():
            if (d.startswith("en") or d.startswith("eth")) and run("ipconfig getifaddr %s 2>/dev/null" % d):
                iface = d; break
    ntype = kind(ports.get(iface, ""))
    ip  = run("ipconfig getifaddr %s 2>/dev/null" % iface) or None
    mac = None
    if iface:
        mm = re.search(r'ether\s+([0-9a-f:]+)', run("ifconfig %s 2>/dev/null" % iface))
        if mm: mac = mm.group(1)
    ssid = rssi = None
    if ntype == "wifi":
        ap = run("networksetup -getairportnetwork %s 2>/dev/null" % iface)
        m = re.search(r'Current Wi-Fi Network:\s*(.+)', ap)
        if m: ssid = m.group(1).strip()
        sp2 = run("system_profiler SPAirPortDataType 2>/dev/null")
        mr = re.search(r'Signal / Noise:\s*(-?\d+)', sp2)
        if mr: rssi = int(mr.group(1))
    return ntype, ip, mac, ssid, rssi

def get_display():
    m = re.search(r'Resolution:\s*(\d+\s*x\s*\d+)', run("system_profiler SPDisplaysDataType 2>/dev/null"))
    return m.group(1).replace(" ", "") if m else None

def get_top_processes():
    top_cpu = top_mem = None
    for l in run("ps -Aceo pcpu,pmem,comm -r | head -6").splitlines():
        l = l.strip()
        if not l or l.startswith("%CPU"): continue
        parts = l.split(None, 2)
        if len(parts) >= 3: top_cpu = "%s %s%%" % (parts[2].split("/")[-1], parts[0]); break
    for l in run("ps -Aceo pcpu,pmem,comm -m | head -6").splitlines():
        l = l.strip()
        if not l or l.startswith("%CPU"): continue
        parts = l.split(None, 2)
        if len(parts) >= 3: top_mem = "%s %s%%" % (parts[2].split("/")[-1], parts[1]); break
    return top_cpu, top_mem

def main():
    st_t, st_u, st_f = get_storage()
    m_t, m_a, m_u, sw_t, sw_u = get_memory()
    b_l, b_s, b_c, b_h = get_battery()
    n_t, n_ip, n_mac, n_ssid, n_rssi = get_network()
    brand, cores, l1, l5, l15 = get_cpu()
    top_cpu, top_mem = get_top_processes()

    data = {
        "model": get_model(), "platform": "Darwin",
        "osVersion": get_os(),
        "appVersion": os.environ.get("RUNETTODAY_VERSION") or "0.1.0",
        "hostname": get_hostname(), "serialNumber": get_serial(),
        "cpuBrand": brand, "cpuCores": cores,
        "cpuLoad1": l1, "cpuLoad5": l5, "cpuLoad15": l15,
        "uptimeSeconds": get_uptime(),
        "storageTotal": st_t, "storageUsed": st_u, "storageFree": st_f,
        "memoryTotal": m_t, "memoryAvailable": m_a, "memoryUsed": m_u,
        "swapTotal": sw_t, "swapUsed": sw_u,
        "batteryLevel": b_l, "batteryState": b_s,
        "batteryCycles": b_c, "batteryHealth": b_h,
        "networkType": n_t, "networkIP": n_ip, "networkMAC": n_mac,
        "wifiSSID": n_ssid, "wifiRSSI": n_rssi,
        "displayRes": get_display(),
        "topCPUProcess": top_cpu, "topMemProcess": top_mem,
    }
    json.dump(data, sys.stdout); sys.stdout.write("\n")

if __name__ == "__main__":
    main()
PY
}

telemetry_send() {
    device_id="$1"
    [ -z "$device_id" ] && { printf '%s\n' "device_id required" >&2; return 1; }
    auth_require_login || return 1
    json="$(telemetry_collect)" || return 1
    api_request POST "/devices/$device_id/telemetry" "$json" "$access_token" >/dev/null || return 1
    printf '%s\n' "Telemetry sent successfully."
}
